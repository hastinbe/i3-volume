#!/bin/bash
#
# i3-volume - Output Format Module
#
# Output format implementations and output format plugins
#
# Note: EXITCODE, EX_URGENT, EX_USAGE are external variables from main script
#

# Format volume for display (show 1 decimal place if needed, otherwise integer)
format_volume_display() {
    local vol=$1
    local unit=${2:-percent}  # "percent" or "db"

    if [ "$unit" = "db" ]; then
        # Display in dB
        local db_value
        db_value=$(percentage_to_db "$vol")
        printf "%.1f" "$db_value"
    else
        # Display in percentage
        # Check if it's effectively a whole number (handle cases like "51.00" or "50.0")
        # Use bc to check if the value equals its integer part
        local int_part
        int_part=$(echo "$vol" | awk '{printf "%.0f", $1}')
        # Compare the original value to the integer part
        if [ "$(echo "$vol == $int_part" | bc -l 2>/dev/null)" = "1" ]; then
            # It's a whole number, display as integer
            printf "%.0f" "$vol"
        else
            # It has a fractional part, display with 1 decimal place
            printf "%.1f" "$vol"
        fi
    fi
}

output_volume_default() {
    if is_muted; then
        echo MUTE
    else
        local vol_raw vol_display unit_suffix
        vol_raw=$(get_volume)
        # Use VOLUME_DISPLAY_UNIT if set, default to percent
        local display_unit="${VOLUME_DISPLAY_UNIT:-percent}"
        vol_display=$(format_volume_display "$vol_raw" "$display_unit")
        if [ "$display_unit" = "db" ]; then
            unit_suffix="dB"
        else
            unit_suffix="%"
        fi
        echo "${vol_display}${unit_suffix}"
    fi
}

# Format options:
#   %v = volume percentage or "MUTE" when muted
#   %n = node display name/alias
#   %d = node id
#   %p = volume progress bar
#   %i = volume icon
output_volume_custom() {
    local -r vol=$(get_volume)
    local format="$1"
    local string

    # Process conditional formatting first (e.g., %v{>50:high:low})
    # This must be done before replacing %v with the actual volume
    while [[ $format =~ %([a-z])\{([^}]+)\} ]]; do
        local placeholder="${BASH_REMATCH[1]}"
        local condition="${BASH_REMATCH[2]}"
        local replacement=""

        # Parse condition: operator:value:true_text:false_text
        # Examples: >50:high:low, <30:quiet:normal, ==100:max:normal
        if [[ $condition =~ ^([<>=!]+)([0-9.]+):(.+):(.+)$ ]]; then
            local op="${BASH_REMATCH[1]}"
            local threshold="${BASH_REMATCH[2]}"
            local true_text="${BASH_REMATCH[3]}"
            local false_text="${BASH_REMATCH[4]}"

            # Get the value to compare based on placeholder
            local compare_val
            case "$placeholder" in
                v) compare_val=$vol ;;
                m) compare_val=$(get_mic_volume 2>/dev/null || echo "0") ;;
                b) compare_val=$(get_balance 2>/dev/null || echo "0") ;;
                *) compare_val=0 ;;
            esac

            # Evaluate condition using decimal comparison
            local condition_result=false
            # Use decimal comparison functions if available, otherwise fall back to integer
            if command_exists bc; then
                case "$op" in
                    ">")  [ "$(echo "$compare_val > $threshold" | bc -l)" = "1" ] && condition_result=true ;;
                    "<")  [ "$(echo "$compare_val < $threshold" | bc -l)" = "1" ] && condition_result=true ;;
                    ">=") [ "$(echo "$compare_val >= $threshold" | bc -l)" = "1" ] && condition_result=true ;;
                    "<=") [ "$(echo "$compare_val <= $threshold" | bc -l)" = "1" ] && condition_result=true ;;
                    "==") [ "$(echo "$compare_val == $threshold" | bc -l)" = "1" ] && condition_result=true ;;
                    "!=") [ "$(echo "$compare_val != $threshold" | bc -l)" = "1" ] && condition_result=true ;;
                esac
            else
                # Fallback to integer comparison
                local compare_int threshold_int
                compare_int=$(printf "%.0f" "$compare_val" 2>/dev/null || echo "0")
                threshold_int=$(printf "%.0f" "$threshold" 2>/dev/null || echo "0")
                case "$op" in
                    ">")  (( compare_int > threshold_int )) && condition_result=true ;;
                    "<")  (( compare_int < threshold_int )) && condition_result=true ;;
                    ">=") (( compare_int >= threshold_int )) && condition_result=true ;;
                    "<=") (( compare_int <= threshold_int )) && condition_result=true ;;
                    "==") (( compare_int == threshold_int )) && condition_result=true ;;
                    "!=") (( compare_int != threshold_int )) && condition_result=true ;;
                esac
            fi

            if [[ "$condition_result" == "true" ]]; then
                replacement="$true_text"
            else
                replacement="$false_text"
            fi
        else
            # Invalid condition format, remove the conditional
            replacement=""
        fi

        # Replace the conditional placeholder with the result
        local conditional_pattern="%${placeholder}{${condition}}"
        format=${format//$conditional_pattern/$replacement}
    done

    # Now process regular placeholders (format volume for display)
    local vol_display unit_suffix
    # Use VOLUME_DISPLAY_UNIT if set, default to percent
    local display_unit="${VOLUME_DISPLAY_UNIT:-percent}"
    vol_display=$(format_volume_display "$vol" "$display_unit")
    if [ "$display_unit" = "db" ]; then
        unit_suffix="dB"
    else
        unit_suffix="%"
    fi
    string=${format//\%v/$vol_display$unit_suffix}
    string=${string//\%n/$(get_node_display_name)}
    string=${string//\%d/$NODE_ID}
    string=${string//\%p/$(progress_bar "$vol")}
    string=${string//\%i/$(get_volume_emoji "$vol")}

    # Replace %s with sink name
    if [[ $string == *%s* ]]; then
        local sink_name="${NODE_NAME:-}"
        string=${string//%s/$sink_name}
    fi

    # Replace %m with microphone volume
    if [[ $string == *%m* ]]; then
        local mic_vol
        if is_mic_muted 2>/dev/null; then
            mic_vol="MUTED"
        else
            mic_vol=$(get_mic_volume 2>/dev/null || echo "N/A")
            if [[ "$mic_vol" != "N/A" ]]; then
                mic_vol=$(format_volume_display "$mic_vol")
            fi
            mic_vol="${mic_vol}%"
        fi
        string=${string//%m/$mic_vol}
    fi

    # Replace %b with balance (function defined in commands.sh, called with error suppression)
    if [[ $string == *%b* ]]; then
        local balance
        balance=$(get_balance 2>/dev/null || echo "0")
        # Format balance: negative = left, positive = right, 0 = center
        if (( balance < 0 )); then
            balance="L${balance#-}"
        elif (( balance > 0 )); then
            balance="R${balance}"
        else
            balance="C"
        fi
        string=${string//%b/$balance}
    fi

    # Replace %c with color codes (function defined in commands.sh, called with error suppression)
    if [[ $string == *%c* ]]; then
        local color_code
        color_code=$(get_volume_color_code "$vol" 2>/dev/null || echo "")
        string=${string//%c/$color_code}
    fi

    # Replace %P with active port description (with availability if available)
    # Functions defined in commands.sh, called with error suppression
    if [[ $string == *%P* ]]; then
        local port_desc port_id port_availability port_info
        port_id=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .value' 2>/dev/null)
        if empty "$port_id"; then
            port_id=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.props."audio.port" // empty' 2>/dev/null)
        fi

        port_desc=$(get_active_port_description 2>/dev/null || echo "")
        if not_empty "$port_id" && not_empty "$port_desc"; then
            # Check availability
            port_availability=$(get_port_availability "$port_id" 2>/dev/null || echo "unknown")
            case "$port_availability" in
                available)
                    port_info="$port_desc [plugged]"
                    ;;
                unavailable)
                    port_info="$port_desc [unplugged]"
                    ;;
                *)
                    port_info="$port_desc"
                    ;;
            esac
        else
            port_info="$port_desc"
        fi
        string=${string//%P/$port_info}
    fi

    # Replace %a with active application name (function defined in commands.sh, called with error suppression)
    if [[ $string == *%a* ]]; then
        local app_name
        app_name=$(get_active_app_name 2>/dev/null || echo "")
        string=${string//%a/$app_name}
    fi

    if is_muted; then echo -ne "${string//\%v/MUTED}"
    else echo -ne "$string"; fi
}

output_volume_i3blocks() {
    local -r name=$(get_node_display_name)
    local short_text

    if is_muted; then
        short_text="<span color=\"$COLOR_MUTED\">MUTED</span>\n"
    else
        local vol_raw vol_display unit_suffix
        vol_raw=$(get_volume)
        # Use VOLUME_DISPLAY_UNIT if set, default to percent
        local display_unit="${VOLUME_DISPLAY_UNIT:-percent}"
        vol_display=$(format_volume_display "$vol_raw" "$display_unit")
        if [ "$display_unit" = "db" ]; then
            unit_suffix="dB"
        else
            unit_suffix="%"
        fi
        short_text="<span color=\"$(volume_color "$vol_raw")\">${vol_display}${unit_suffix}</span>\n"
        local effective_max_vol
        effective_max_vol=$(get_effective_max_vol)
        # Use decimal comparison for max volume check
        if not_empty "$effective_max_vol" && [ "$(echo "$vol_raw > $effective_max_vol" | bc -l 2>/dev/null)" = "1" ]; then
            # shellcheck disable=SC2034  # EXITCODE and EX_URGENT are external variables from main script
            EXITCODE=$EX_URGENT
        fi
    fi

    local full_text=${short_text}
    not_empty "$name" && full_text="<span color=\"$COLOR_TEXT\">$name</span> $short_text"

    echo -ne "$full_text$short_text"
}

output_volume_xob() {
    local vol_raw vol_display unit_suffix
    vol_raw=$(get_volume)
    # Use VOLUME_DISPLAY_UNIT if set, default to percent
    local display_unit="${VOLUME_DISPLAY_UNIT:-percent}"
    vol_display=$(format_volume_display "$vol_raw" "$display_unit")
    if [ "$display_unit" = "db" ]; then
        unit_suffix="dB"
    else
        unit_suffix="%"
    fi
    echo "${vol_display}${unit_suffix}$(is_muted && echo "!")"
}

output_volume_json() {
    local vol muted display_name port_desc app_name mic_vol mic_muted balance
    local json_output

    # Get volume and muted status
    vol=$(get_volume)
    if is_muted; then
        muted="true"
    else
        muted="false"
    fi

    # Get display name
    display_name=$(get_node_display_name)

    # Get port description (may be empty, function defined in commands.sh)
    port_desc=$(get_active_port_description 2>/dev/null || echo "")

    # Get active app name (may be empty, function defined in commands.sh)
    app_name=$(get_active_app_name 2>/dev/null || echo "")

    # Get balance (may not be available, function defined in commands.sh)
    balance=$(get_balance 2>/dev/null || echo "0")

    # Get microphone information (may not be available)
    if is_mic_muted 2>/dev/null; then
        mic_muted="true"
        mic_vol=""
    else
        mic_muted="false"
        mic_vol=$(get_mic_volume 2>/dev/null || echo "")
    fi

    # Build JSON using jq for proper escaping and formatting
    json_output=$(jq -n \
        --arg volume "$vol" \
        --arg sink_name "${NODE_NAME:-}" \
        --arg node_id "${NODE_ID:-}" \
        --arg display_name "$display_name" \
        --arg port "${port_desc:-}" \
        --arg active_app "${app_name:-}" \
        --arg mic_volume "${mic_vol:-}" \
        --arg muted_str "$muted" \
        --arg mic_muted_str "$mic_muted" \
        --arg balance_str "$balance" \
        '{
            volume: ($volume | tonumber),
            muted: ($muted_str == "true"),
            sink_name: (if $sink_name == "" then null else $sink_name end),
            node_id: (if $node_id == "" then null else ($node_id | tonumber) end),
            display_name: (if $display_name == "" then null else $display_name end),
            port: (if $port == "" then null else $port end),
            active_app: (if $active_app == "" then null else $active_app end),
            balance: ($balance_str | tonumber),
            microphone: {
                volume: (if $mic_volume == "" then null else ($mic_volume | tonumber) end),
                muted: ($mic_muted_str == "true")
            }
        }' 2>/dev/null)

    # Fallback to manual JSON construction if jq fails
    if [[ -z "$json_output" ]]; then
        # Escape strings for JSON (simple escaping)
        escape_json() {
            echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'
        }

        local esc_display_name esc_port esc_app_name esc_sink_name
        esc_display_name=$(escape_json "$display_name")
        esc_port=$(escape_json "$port_desc")
        esc_app_name=$(escape_json "$app_name")
        esc_sink_name=$(escape_json "${NODE_NAME:-}")

        json_output="{"
        json_output="${json_output}\"volume\":${vol},"
        json_output="${json_output}\"muted\":${muted},"
        if [[ -n "$NODE_NAME" ]]; then
            json_output="${json_output}\"sink_name\":\"${esc_sink_name}\","
        else
            json_output="${json_output}\"sink_name\":null,"
        fi
        if [[ -n "$NODE_ID" ]]; then
            json_output="${json_output}\"node_id\":${NODE_ID},"
        else
            json_output="${json_output}\"node_id\":null,"
        fi
        if [[ -n "$display_name" ]]; then
            json_output="${json_output}\"display_name\":\"${esc_display_name}\","
        else
            json_output="${json_output}\"display_name\":null,"
        fi
        if [[ -n "$port_desc" ]]; then
            json_output="${json_output}\"port\":\"${esc_port}\","
        else
            json_output="${json_output}\"port\":null,"
        fi
        if [[ -n "$app_name" ]]; then
            json_output="${json_output}\"active_app\":\"${esc_app_name}\","
        else
            json_output="${json_output}\"active_app\":null,"
        fi
        json_output="${json_output}\"balance\":${balance},"
        json_output="${json_output}\"microphone\":{"
        if [[ -n "$mic_vol" ]]; then
            json_output="${json_output}\"volume\":${mic_vol},"
        else
            json_output="${json_output}\"volume\":null,"
        fi
        json_output="${json_output}\"muted\":${mic_muted}"
        json_output="${json_output}}}"
    fi

    echo "$json_output"
}

# Output format plugin wrappers (use generalized plugin system from helpers.sh)
call_output_plugin() {
    local plugin_name=$1
    shift
    # Output plugins use function name: output_volume_<name>
    local func_name="output_volume_$plugin_name"

    # Load plugin using generalized system (plugins stored in plugins/output/ directory)
    if ! load_plugin "output" "$plugin_name"; then
        return 1
    fi

    # Check if the function exists
    if ! declare -f "$func_name" >/dev/null 2>&1; then
        error "Output plugin $plugin_name does not define function: $func_name"
        return 1
    fi

    # Call the plugin function
    "$func_name" "$@"
}

is_output_plugin_available() {
    is_plugin_available "output" "$1"
}

list_output_plugins() {
    list_plugins "output"
}

output_volume() {
    local -r for=${1:?$(error 'Output method is required')}

    case "$for" in
        i3blocks ) output_volume_i3blocks ;;
        xob      ) output_volume_xob ;;
        json     ) output_volume_json ;;
        default  ) output_volume_default ;;
        *        )
            # Check if it's a plugin first
            if is_output_plugin_available "$for"; then
                call_output_plugin "$for" || output_volume_custom "$*"
            else
                output_volume_custom "$*"
            fi
            ;;
    esac
}

list_output_formats() {
    # List built-in formats from main script
    local script_dir
    script_dir=$(get_script_dir)
    local main_script="$script_dir/volume"

    # shellcheck disable=SC2034  # EXITCODE and EX_USAGE are external variables from main script
    awk 'match($0,/ +output_volume_([[:alnum:]]+)\(\)/) {print substr($0, RSTART + 18, RLENGTH - 20)}' "$main_script" 2>/dev/null || EXITCODE=$EX_USAGE
    # List output plugins
    list_output_plugins
}

