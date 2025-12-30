#!/bin/bash
#
# i3-volume - Audio Control Module
#
# PipeWire/WirePlumber audio control functions
#

# Volume getters/setters
get_volume() { wpctl get-volume "$NODE_ID" | awk '{print $2 * 100}'; }
is_muted() { wpctl get-volume "$NODE_ID" | grep -q '\[MUTED\]'; }

get_mic_volume() {
    if empty "$SOURCE_ID"; then
        init_source
    fi
    wpctl get-volume "$SOURCE_ID" 2>/dev/null | awk '{print $2 * 100}'
}

is_mic_muted() {
    if empty "$SOURCE_ID"; then
        init_source
    fi
    wpctl get-volume "$SOURCE_ID" 2>/dev/null | grep -q '\[MUTED\]'
}

# Icon and emoji functions
get_volume_icon() {
    local -r vol=${1:?$(error 'Volume is required')}
    local icon

    if $USE_FULLCOLOR_ICONS; then
        if (( vol >= 70 )); then icon=${ICONS[1]}
        elif (( vol >= 40 )); then icon=${ICONS[3]}
        elif (( vol > 0 )); then icon=${ICONS[2]}
        else icon=${ICONS[2]}
        fi
    else
        # Get overamplified icon if available, otherwise default to high volume icon
        if (( vol > 100 )); then icon=${ICONS_SYMBOLIC[4]:-${ICONS_SYMBOLIC[1]}}
        elif (( vol >= 70 )); then icon=${ICONS_SYMBOLIC[1]}
        elif (( vol >= 40 )); then icon=${ICONS_SYMBOLIC[3]}
        elif (( vol > 0 )); then icon=${ICONS_SYMBOLIC[2]}
        else icon=${ICONS_SYMBOLIC[2]}
        fi
    fi

    echo "$icon"
}

get_volume_emoji() {
    local -r vol=${1:?$(error 'Volume is required')}
    local icon

    if is_muted; then icon=${ICONS_EMOJI[0]}
    else
        if (( vol >= 70 )); then icon=${ICONS_EMOJI[1]}
        elif (( vol >= 40 )); then icon=${ICONS_EMOJI[3]}
        elif (( vol > 0 )); then icon=${ICONS_EMOJI[2]}
        else icon=${ICONS_EMOJI[2]}
        fi
    fi
    echo "$icon"
}

# Status bar functions
update_statusline() {
    local signal=${1:?$(error 'Signal is required')}
    local proc=${2:?$(error 'Process name is required')}
    pkill "-$signal" "$proc"
}

progress_bar() {
    local percent=${1:?$(error 'Percentage is required')}
    local -i max_percent=${2:-100}
    local -i bar_length=${3:-20}

    # Clamp the percentage to be within 0 and max_percent
    (( percent = percent < 0 ? 0 : (percent > max_percent ? max_percent : percent) ))

    local filled_blocks=$(( percent * bar_length / max_percent ))
    local empty_blocks=$(( bar_length - filled_blocks ))
    local bar; printf -v bar "%${filled_blocks}s" ''
    local empty; printf -v empty "%${empty_blocks}s" ''

    echo "${bar// /█}${empty// /░}"
}

apply_symbolic_icon_suffix() {
    for i in "${!ICONS_SYMBOLIC[@]}"; do
        ICONS_SYMBOLIC[i]="${ICONS_SYMBOLIC[i]}${SYMBOLIC_ICON_SUFFIX}"
    done
}

volume_color() {
    local -ir vol=${1:?$(error 'A volume is required')}
    local effective_max_vol
    effective_max_vol=$(get_effective_max_vol)
    if (( vol >= MIN_VOL && vol < DEFAULT_VOL )); then echo "$COLOR_MIN_TO_DEFAULT";
    elif (( vol == 100 )); then echo "$COLOR_FULL";
    elif (( vol > 100 && vol <= effective_max_vol )); then echo "$COLOR_FULL_TO_MAX";
    else echo "$COLOR_OTHER";
    fi
}

update_statusbar() {
    # shellcheck disable=SC2153  # SIGNAL is a global variable from main script
    if not_empty "$SIGNAL" && empty "$STATUSLINE"; then return 1; fi
    if not_empty "$SIGNAL"; then update_statusline "$SIGNAL" "$STATUSLINE";
    elif not_empty "$STATUSLINE"; then return 1; fi
    return 0
}

# Audio initialization
init_audio() {
    # Check if PipeWire is running
    if ! check_pipewire_running; then
        error_with_suggestion "PipeWire is not running or not accessible." \
            "Check if PipeWire is running: systemctl --user status pipewire pipewire-pulse" \
            "Start PipeWire if needed: systemctl --user start pipewire pipewire-pulse"
        if [[ "${VERBOSE:-false}" == "true" ]]; then
            local diag
            diag=$(get_pipewire_diagnostics)
            if not_empty "$diag"; then
                echo "${COLOR_CYAN}[verbose]${COLOR_RESET} $diag" >&2
            fi
        fi
        exit "$EX_UNAVAILABLE"
    fi

    # Check if wpctl is available
    if ! check_wpctl_available; then
        error_with_suggestion "wpctl command not found." \
            "Install WirePlumber package for your distribution."
        exit "$EX_UNAVAILABLE"
    fi

    if empty "$NODE_NAME"; then
        local default_sink_output
        if ! default_sink_output=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>&1); then
            error_with_suggestion "Cannot access default audio sink." \
                "PipeWire may not be fully initialized. Try: systemctl --user restart pipewire pipewire-pulse" \
                "Use 'volume list sinks' to see available sinks."
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo "${COLOR_CYAN}[verbose]${COLOR_RESET} wpctl output: $default_sink_output" >&2
            fi
            exit "$EX_UNAVAILABLE"
        fi
        NODE_NAME=$(echo "$default_sink_output" | awk '/[ \*]+node\.name/{gsub(/"/, "", $4); print $4}')
    fi

    NODE_ID=$(get_node_id)

    if empty "$NODE_ID"; then
        error_with_suggestion "Sink not found: $NODE_NAME" \
            "Use 'volume list sinks' to see available sinks." \
            "Specify a different sink with: volume -s <sink_name> <command>"
        if [[ "${VERBOSE:-false}" == "true" ]]; then
            echo "${COLOR_CYAN}[verbose]${COLOR_RESET} Attempted to find sink: $NODE_NAME" >&2
            local available_sinks
            available_sinks=$(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink") | .info.props."node.name"' 2>/dev/null | head -5)
            if not_empty "$available_sinks"; then
                echo "${COLOR_CYAN}[verbose]${COLOR_RESET} Available sinks:" >&2
                echo "$available_sinks" | while read -r sink; do
                    echo "${COLOR_CYAN}[verbose]${COLOR_RESET}   - $sink" >&2
                done
            fi
        fi
        exit "$EX_UNAVAILABLE"
    fi

    NODE_NICK=$(get_node_nick)
    DEFAULT_VOL=$(get_default_volume)
    MIN_VOL=$(get_min_volume)
    # shellcheck disable=SC2034  # MAX_VOL is a global variable used across modules
    MAX_VOL=$(get_max_volume)
}

init_source() {
    if empty "$SOURCE_NAME"; then
        SOURCE_NAME=$(wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '/[ \*]+node\.name/{gsub(/"/, "", $4); print $4}')
    fi
    SOURCE_ID=$(get_source_id)
    # shellcheck disable=SC2034  # SOURCE_NICK may be used in future features
    SOURCE_NICK=$(get_source_nick)
}

# Node/sink management
get_node_id() {
    pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."node.name" == "'"$NODE_NAME"'") | .id'
}

get_node_nick() {
    pw_dump | jq -r '.[] | select(.id == '"$NODE_ID"') | .info.props."node.nick"'
}

get_source_id() {
    pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."node.name" == "'"$SOURCE_NAME"'") | .id'
}

get_source_nick() {
    pw_dump | jq -r '.[] | select(.id == '"$SOURCE_ID"') | .info.props."node.nick"'
}

get_node_display_name() {
    if isset NODE_ALIASES["$NODE_ID"]; then echo "${NODE_ALIASES[$NODE_ID]}"
    elif isset NODE_ALIASES["$NODE_NAME"]; then echo "${NODE_ALIASES[$NODE_NAME]}"
    elif isset NODE_ALIASES["$NODE_NICK"]; then echo "${NODE_ALIASES[$NODE_NICK]}"
    else get_node_nick
    fi
}

# Cache management
pw_dump() {
    if [[ $COMMAND == "listen" ]] || empty "$PW_DUMP"; then
        PW_DUMP=$(pw-dump)
    fi
    echo "$PW_DUMP"
}

invalidate_cache() {
    PW_DUMP=""
}

# Volume info functions
get_volume_info() {
    local -r type=${1:?$(error 'Volume type (default/min/max) is required')}
    local vol
    vol=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "volume") | .type.'"$type"'' 2>/dev/null)

    empty "$vol" && { echo "Error: $type volume information not found for NODE_ID=$NODE_ID" >&2; return 1; }
    echo "$vol" | awk '{print $1 * 100}'
}

get_default_volume() {
    get_volume_info "default"
}

get_min_volume() {
    get_volume_info "min"
}

get_max_volume() {
    get_volume_info "max"
}

pw_play() {
    command_exists pw-play || { error "pw-play is not installed or not in \$PATH"; return 1; }
    pw-play --target "$NODE_ID" "$1" &
}

