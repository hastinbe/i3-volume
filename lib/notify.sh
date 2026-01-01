#!/bin/bash
#
# i3-volume - Notification Module
#
# Notification system and notification method implementations
#
# Note: EXITCODE, EX_USAGE are external variables from main script
#

# Notification-specific plugin wrappers (use generalized plugin system from define_helpers)
call_notification_plugin() {
    local plugin_name=$1
    shift
    # Notification plugins use function name: notify_volume_<name>
    local func_name="notify_volume_$plugin_name"

    # Load plugin using generalized system (plugins stored in plugins/notify/ directory)
    if ! load_plugin "notify" "$plugin_name"; then
        return 1
    fi

    # Check if the function exists
    if ! declare -f "$func_name" >/dev/null 2>&1; then
        error "Notification plugin $plugin_name does not define function: $func_name"
        return 1
    fi

    # Call the plugin function
    "$func_name" "$@"
}

is_notification_plugin_available() {
    is_plugin_available "notify" "$1"
}

list_notification_plugins() {
    list_plugins "notify"
}

# Check if multiple sinks are available
has_multiple_sinks() {
    local sinks
    readarray -t sinks < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink") | .id' 2>/dev/null)
    [[ ${#sinks[@]} -gt 1 ]]
}

notify_volume() {
    local -r vol=$(get_volume)
    local icon summary body=""
    local boost_info=""

    # Check if boost is active (function defined in commands.sh, called with error suppression)
    if is_boost_active 2>/dev/null; then
        boost_info=" (+${BOOST_AMOUNT}% boost)"
    fi

    # Build summary with sink name if multiple sinks available
    local sink_info=""
    if has_multiple_sinks; then
        local sink_display_name
        sink_display_name=$(get_node_display_name)
        sink_info=" ($sink_display_name)"
    fi

    # Get current port information (functions defined in commands.sh, called with error suppression)
    local port_info=""
    local port_desc current_port_id
    current_port_id=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .value' 2>/dev/null)
    if empty "$current_port_id"; then
        current_port_id=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.props."audio.port" // empty' 2>/dev/null)
    fi

    port_desc=$(get_active_port_description 2>/dev/null || echo "")
    if not_empty "$port_desc"; then
        port_info=" - $port_desc"
    fi

    # Check if port changed
    local last_port_id port_changed=false
    last_port_id=$(get_last_port 2>/dev/null || echo "")
    if not_empty "$current_port_id" && not_empty "$last_port_id" && [[ "$current_port_id" != "$last_port_id" ]]; then
        port_changed=true
        # Enhance port info to indicate change
        if not_empty "$port_desc"; then
            port_info=" - $port_desc ${COLOR_YELLOW}[changed]${COLOR_RESET}"
        fi
    fi

    # Save current port for next comparison (function defined in commands.sh, called with error suppression)
    if not_empty "$current_port_id"; then
        save_last_port "$current_port_id" 2>/dev/null || true
    fi

    if is_muted; then
        summary="Volume muted${sink_info}${port_info}"
        icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[0]}" || echo "${ICONS_SYMBOLIC[0]}")
    else
        # Format volume for display (show whole numbers without decimals)
        local vol_display
        vol_display=$(format_volume_display "$vol")
        printf -v summary "Volume %3s%%%s%s%s" "$vol_display" "$boost_info" "$sink_info" "$port_info"
        icon=$(get_volume_icon "$vol")

        if $SHOW_VOLUME_PROGRESS; then
            local -r progress=$(progress_bar "$vol")
            if has_capability body && [[ $PROGRESS_PLACEMENT == body ]]; then body="$progress"
            else summary="$summary $progress"; fi
        fi
    fi

    case "$NOTIFICATION_METHOD" in
        libnotify|dunst|notify-osd)
            notify_volume_libnotify "$vol" "$icon" "$summary" "$body"
            ;;
        *)
            # Check if it's a plugin (built-in or user)
            if is_notification_plugin_available "$NOTIFICATION_METHOD"; then
                call_notification_plugin "$NOTIFICATION_METHOD" "$vol" "$icon" "$summary" "$body" || notify_volume_libnotify "$vol" "$icon" "$summary" "$body"
            else
                notify_volume_libnotify "$vol" "$icon" "$summary" "$body"
            fi
            ;;
    esac

    # Check for newly available ports and suggest switching (only if port didn't just change)
    # Function defined in commands.sh, called with error suppression
    if [[ "$port_changed" == "false" ]]; then
        detect_and_suggest_port_switch || true
    fi
}

notify_mic() {
    if empty "$SOURCE_ID"; then
        init_source
    fi

    if empty "$SOURCE_ID"; then
        return 1
    fi

    local -r vol=$(get_mic_volume)
    local icon summary body=""

    if is_mic_muted; then
        summary="Microphone muted"
        icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[0]}" || echo "${ICONS_SYMBOLIC[0]}")
    else
        printf -v summary "Microphone %3s%%" "$vol"
        icon=$(get_volume_icon "$vol")

        if $SHOW_VOLUME_PROGRESS; then
            local -r progress=$(progress_bar "$vol")
            if has_capability body && [[ $PROGRESS_PLACEMENT == body ]]; then body="$progress"
            else summary="$summary $progress"; fi
        fi
    fi

    case "$NOTIFICATION_METHOD" in
        libnotify|dunst|notify-osd)
            notify_volume_libnotify "$vol" "$icon" "$summary" "$body"
            ;;
        *)
            # Check if it's a plugin (built-in or user)
            if is_notification_plugin_available "$NOTIFICATION_METHOD"; then
                call_notification_plugin "$NOTIFICATION_METHOD" "$vol" "$icon" "$summary" "$body" || notify_volume_libnotify "$vol" "$icon" "$summary" "$body"
            else
                notify_volume_libnotify "$vol" "$icon" "$summary" "$body"
            fi
            ;;
    esac
}

list_notification_methods() {
    local source="${BASH_SOURCE[0]}"
    # Walk up to find the main volume script
    local script_dir
    script_dir=$(get_script_dir)
    local main_script="$script_dir/volume"

    # List built-in methods from main script
    # shellcheck disable=SC2034  # EXITCODE and EX_USAGE are external variables from main script
    awk 'match($0, / +notify_volume_([[:alnum:]]+)\(\)/) { print substr($0, RSTART + 18, RLENGTH - 20) }' "$main_script" 2>/dev/null || EXITCODE=$EX_USAGE
    # List notification plugins
    list_notification_plugins
}

setup_notification_icons() {
    not_empty "$SYMBOLIC_ICON_SUFFIX" && apply_symbolic_icon_suffix
}

show_volume_notification() {
    $DISPLAY_NOTIFICATIONS || return

    if empty "$NOTIFICATION_METHOD"; then
        load_notify_server_info
        NOTIFICATION_METHOD=$NOTIFY_SERVER
    fi

    setup_notification_icons
    notify_volume
}

load_notify_server_info() {
    command_exists dbus-send || return
    IFS=$'\t' read -r NOTIFY_SERVER _ _ _ < <(dbus-send --print-reply --dest=org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications.GetServerInformation | awk 'BEGIN { ORS="\t" }; match($0, /^   string ".*"/) {print substr($0, RSTART+11, RLENGTH-12)}')
}

load_notify_server_caps() {
    command_exists dbus-send || return
    IFS= read -r -d '' -a NOTIFY_CAPS < <(dbus-send --print-reply=literal --dest="${DBUS_NAME}" "${DBUS_PATH}" "${DBUS_IFAC_FDN}.GetCapabilities" | awk 'RS="      " { if (NR > 2) print $1 }')
}

notify_volume_libnotify() {
    local vol=$1 icon=$2 summary=$3 body=${*:4}
    local args=('-t' "$EXPIRES")
    local hints=(
        'string:synchronous:volume'                     # Replace previous notification in some notification servers
        'string:x-canonical-private-synchronous:volume' # Replace previous notification in NotifyOSD
    )
    local executable

    # Add progress hint if we're not drawing our own (if supported)
    $SHOW_VOLUME_PROGRESS || hints+=( "int:value:$vol" )

    # Load notification server capabilities if not already loaded
    [[ ${#NOTIFY_CAPS[@]} -lt 1 ]] && load_notify_server_caps

    # Add icon hints if supported
    if has_capability icon-static || has_capability icon-multi; then
        args+=( '-i' "$icon" )
        hints+=( "string:image-path:$icon" ) # For linux_notification_center, supports string:image-path instead of -i|--icon
    fi

    # Add sound hint if sound is enabled and supported
    $PLAY_SOUND && has_capability sound && hints+=( "string:sound-name:audio-volume-change" )

    # Dunst-specific options
    if [[ $NOTIFICATION_METHOD == "dunst" ]]; then
        # Use grouping tag if notification grouping is enabled
        local group_tag="volume"
        if isset NOTIFICATION_GROUP && [[ "$NOTIFICATION_GROUP" == "true" ]]; then
            group_tag="volume-group"
        fi
        hints+=( "string:x-dunst-stack-tag:$group_tag" )
        if ! isset NO_NOTIFY_COLOR; then
            local color
            if is_muted; then color=$COLOR_MUTED; else color=$(volume_color "$vol"); fi
            hints+=( "string:fgcolor:$color" )
        fi
    fi

    # Determine executable and additional arguments
    if $USE_DUNSTIFY; then
        executable="${NOTIFY_PATH:+${NOTIFY_PATH%/}/}dunstify"
        args+=( '-r' 1000 )

        # Transient notifications will bypass the idle_threshold setting.
        # Should be boolean, but Notify-OSD doesn't support boolean yet. Dunst checks
        # for int and bool with transient so use what works with both servers.
        hints+=( "int:transient:1" )
    elif isset USE_NOTIFY_SEND_PY; then
        executable="${NOTIFY_PATH:+${NOTIFY_PATH%/}/}notify-send.py"
        args+=( --replaces-process volume ) # Replaces previous notification, but leaves itself running in the bg to work
        hints+=( "boolean:transient:true" ) # By-pass the server's persistence capability, if it should exist
        hints=( "${hints[@]/#/--hint }" ) # Prefix all hints with --hint to work with notify-send.py
    else
        executable="${NOTIFY_PATH:+${NOTIFY_PATH%/}/}notify-send"
    fi

    command_exists "$executable" || { error "$executable not found. Please install it or set NOTIFY_PATH to the correct path."; exit "$EX_UNAVAILABLE"; }

    read -ra hints <<< "${hints[@]/#/-h }"
    "$executable" "${hints[@]}" "${args[@]}" "$summary" "$body" &
}

