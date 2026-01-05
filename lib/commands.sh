#!/bin/bash
#
# i3-volume - Commands Module
#
# Command implementations
#
# Note: EXITCODE, EX_OK, EX_URGENT, EX_USAGE, EX_UNAVAILABLE, and COLOR_* variables
# are external variables from main script
#
# shellcheck disable=SC2034  # EXITCODE, EX_*, and COLOR_* are external variables from main script
#

fade_volume() {
     local -r target_vol=$1
     local -r duration_ms=$2
     local -r node_id=$3
     local -r start_vol=${4:-}  # Optional starting volume
     local current_vol target_vol_int
     local -i steps=50  # Number of steps for smooth fade
     local -i step_delay

     if not_empty "$start_vol"; then
         # Convert decimal to integer for fade steps (wpctl rounds anyway)
         current_vol=$(printf "%.0f" "$start_vol" 2>/dev/null || echo "${start_vol%.*}")
     else
         current_vol=$(get_volume)
         # Convert to integer for fade steps
         current_vol=$(printf "%.0f" "$current_vol" 2>/dev/null || echo "${current_vol%.*}")
     fi
     # Round target volume to integer (wpctl will round anyway)
     target_vol_int=$(printf "%.0f" "$target_vol" 2>/dev/null || echo "${target_vol%.*}")

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         local node_display
         node_display=$(get_node_display_name 2>/dev/null || echo "sink $node_id")
         dry_run_msg "Would fade volume from ${current_vol}% to ${target_vol_int}% over ${duration_ms}ms on $node_display"
         dry_run_msg "  Current volume: ${current_vol}%"
         dry_run_msg "  Target volume: ${target_vol_int}%"
         dry_run_msg "  Duration: ${duration_ms}ms (${steps} steps, ~$(( duration_ms / steps ))ms per step)"
         return 0
     fi

     # Calculate step delay in milliseconds
     if (( duration_ms > 0 && steps > 0 )); then
         step_delay=$(( duration_ms / steps ))
     else
         step_delay=10  # Default 10ms per step
     fi

     # Calculate volume difference
     local -i vol_diff=$(( target_vol_int - current_vol ))

     if (( vol_diff == 0 )); then
         return 0  # Already at target
     fi

     # Calculate step size
     local -i step_size
     if (( vol_diff > 0 )); then
         step_size=$(( (vol_diff + steps - 1) / steps ))  # Ceiling division
     else
         step_size=$(( (vol_diff - steps + 1) / steps ))  # Floor division
     fi

     # Perform fade
     local -i i
     for (( i = 0; i < steps; i++ )); do
         local -i new_vol=$(( current_vol + step_size * (i + 1) ))

         # Clamp to target
         if (( vol_diff > 0 && new_vol > target_vol_int )); then
             new_vol=$target_vol_int
         elif (( vol_diff < 0 && new_vol < target_vol_int )); then
             new_vol=$target_vol_int
         fi

         # Clamp to valid range
         if (( new_vol < 0 )); then
             new_vol=0
         else
             local effective_max_vol
             effective_max_vol=$(get_effective_max_vol)
             if not_empty "$effective_max_vol" && (( new_vol > effective_max_vol )); then
                 new_vol=$effective_max_vol
             fi
         fi

         wpctl set-volume "$node_id" "${new_vol}%" &>/dev/null

         # Sleep between steps (convert ms to microseconds for usleep, or use sleep)
         if (( i < steps - 1 )); then
             if command -v usleep &>/dev/null; then
                 # usleep takes microseconds
                 usleep $(( step_delay * 1000 )) 2>/dev/null || sleep 0.01
             else
                 # sleep with decimal seconds (bash 4+ supports this)
                 local sleep_time
                 sleep_time=$(awk "BEGIN {printf \"%.3f\", $step_delay / 1000}" 2>/dev/null)
                 if [[ -n "$sleep_time" ]]; then
                     sleep "$sleep_time" 2>/dev/null || sleep 0.01
                 else
                     sleep 0.01
                 fi
             fi
         fi
     done

     # Ensure we end at exact target (rounded)
     wpctl set-volume "$node_id" "${target_vol_int}%" &>/dev/null
     invalidate_cache
 }

set_volume() {
     local -r vol_input=${1:?$(error 'Volume is required')}
     local -r op=${2:-}

     # Check if operating on all sinks
     if $ALL_SINKS; then
         set_volume_all "$vol_input" "$op"
         return
     fi

     # Detect if input is in dB or percentage, and convert to percentage for internal use
     local vol vol_unit is_relative_db=false
     vol_unit=$(detect_volume_unit "$vol_input")
     if [ "$vol_unit" = "db" ]; then
         # For relative operations with dB, we need special handling
         if [ "$op" = "+" ] || [ "$op" = "-" ]; then
             # Relative dB operation: convert current volume to dB, add/subtract, convert back
             # This gives us the target volume directly
             local current_vol current_db new_db
             current_vol=$(get_volume 2>/dev/null || echo "0")
             current_db=$(percentage_to_db "$current_vol")
             # Extract numeric part from dB input (remove "dB", "db", "DB", or "Db" suffix)
             local db_value
             if [[ "$vol_input" =~ ^(.+)[dD][bB]$ ]]; then
                 db_value="${BASH_REMATCH[1]}"
             else
                 db_value="$vol_input"
             fi
             if [ "$op" = "+" ]; then
                 new_db=$(decimal_add "$current_db" "$db_value")
             else
                 new_db=$(decimal_subtract "$current_db" "$db_value")
             fi
             vol=$(db_to_percentage "$new_db")
             is_relative_db=true
         else
             # Absolute dB value: convert to percentage
             vol=$(parse_volume_value "$vol_input")
         fi
     else
         # Already in percentage
         vol="$vol_input"
     fi

     # Save current volume to history before making changes
     local current_vol
     current_vol=$(get_volume 2>/dev/null || echo "0")

     # Log volume operation
     if not_empty "${LOG_FILE:-}"; then
         local node_display
         node_display=$(get_sink_nick 2>/dev/null || echo "sink $NODE_ID")
         local op_desc
         case "$op" in
             +) op_desc="increase by $vol_input" ;;
             -) op_desc="decrease by $vol_input" ;;
             *) op_desc="set to $vol_input" ;;
         esac
         log_volume_operation "set_volume" "node: $node_display" "operation: $op_desc" "current: ${current_vol}%"
         if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
             log_debug "Volume calculation: input=$vol_input, unit=$vol_unit, calculated_vol=$vol, operation=$op"
         fi
     fi

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         local node_display
         node_display=$(get_node_display_name 2>/dev/null || echo "sink $NODE_ID")
         local effective_max_vol
         effective_max_vol=$(get_effective_max_vol)
         local target_vol

         # Calculate target volume based on operation
         case "$op" in
             +)
                 if [ "$is_relative_db" = "true" ]; then
                     target_vol="$vol"
                 else
                     target_vol=$(decimal_add "$current_vol" "$vol")
                 fi
                 ;;
             -)
                 if [ "$is_relative_db" = "true" ]; then
                     target_vol="$vol"
                 else
                     target_vol=$(decimal_subtract "$current_vol" "$vol")
                 fi
                 ;;
             *)
                 target_vol="$vol"
                 ;;
         esac

         # Check max volume constraint
         if not_empty "$effective_max_vol" && [ "$(decimal_gt "$target_vol" "$effective_max_vol")" = "1" ]; then
             target_vol="$effective_max_vol"
             dry_run_msg "Would set volume on $node_display (clamped to max: ${effective_max_vol}%)"
         else
             dry_run_msg "Would set volume on $node_display"
         fi

         dry_run_msg "  Current volume: ${current_vol}%"
         if [ "$vol_unit" = "db" ]; then
             local current_db target_db
             current_db=$(percentage_to_db "$current_vol")
             target_db=$(percentage_to_db "$target_vol")
             dry_run_msg "  Input: ${vol_input} (${vol_unit})"
             dry_run_msg "  Current: ${current_vol}% (${current_db}dB)"
             dry_run_msg "  Target: ${target_vol}% (${target_db}dB)"
         else
             dry_run_msg "  Input: ${vol_input}%"
             if [ "$op" = "+" ]; then
                 dry_run_msg "  Operation: increase by ${vol}%"
             elif [ "$op" = "-" ]; then
                 dry_run_msg "  Operation: decrease by ${vol}%"
             else
                 dry_run_msg "  Operation: set to ${vol}%"
             fi
             dry_run_msg "  Target volume: ${target_vol}%"
         fi
         if not_empty "$effective_max_vol"; then
             dry_run_msg "  Max volume: ${effective_max_vol}%"
         fi
         if not_empty "$FADE_DURATION"; then
             dry_run_msg "  Fade duration: ${FADE_DURATION}ms"
         fi
         return 0
     fi

     save_volume_to_history "$current_vol"

     local target_vol
     local effective_max_vol
     effective_max_vol=$(get_effective_max_vol)

     if not_empty "$effective_max_vol"; then
         case "$op" in
             +)  # Increase volume
                 # For relative dB operations, vol is already the target, don't add again
                 local sum_vol
                 if [ "$is_relative_db" = "true" ]; then
                     sum_vol="$vol"
                 else
                     sum_vol=$(decimal_add "$current_vol" "$vol")
                 fi
                 if [ "$(decimal_gt "$sum_vol" "$effective_max_vol")" = "1" ]; then
                     # Instead of doing nothing, step to max_volume
                     local step
                     step=$(decimal_subtract "$effective_max_vol" "$current_vol")
                     # Ensure step is not negative
                     if [ "$(decimal_lt "$step" "0")" = "1" ]; then
                         step="0"
                     fi
                     local step_int
                     step_int=$(printf "%.0f" "$step")
                     if not_empty "$FADE_DURATION"; then
                         fade_volume "$effective_max_vol" "$FADE_DURATION" "$NODE_ID"
                     else
                         wpctl set-volume "$NODE_ID" "${step_int}%+"
                     fi
                     return
                 fi
                 ;;
             *)  # Set absolute volume
                 if [ "$(decimal_gt "$vol" "$effective_max_vol")" = "1" ]; then
                     return
                 fi
                 ;;
         esac
     fi

     # Handle fade if requested
     if not_empty "$FADE_DURATION"; then
         case "$op" in
             +)
                 # For relative dB operations, vol is already the target
                 if [ "$is_relative_db" = "true" ]; then
                     target_vol="$vol"
                 else
                     target_vol=$(decimal_add "$current_vol" "$vol")
                 fi
                 fade_volume "$target_vol" "$FADE_DURATION" "$NODE_ID"
                 ;;
             -)
                 # For relative dB operations, vol is already the target
                 if [ "$is_relative_db" = "true" ]; then
                     target_vol="$vol"
                 else
                     target_vol=$(decimal_subtract "$current_vol" "$vol")
                 fi
                 fade_volume "$target_vol" "$FADE_DURATION" "$NODE_ID"
                 ;;
             *)
                 fade_volume "$vol" "$FADE_DURATION" "$NODE_ID"
                 ;;
         esac
     else
         invalidate_cache
         case "$op" in
             +)
                 # For relative dB operations, vol is already the target percentage
                 if [ "$is_relative_db" = "true" ]; then
                     wpctl set-volume "$NODE_ID" "${vol}%"
                 else
                     wpctl set-volume "$NODE_ID" "${vol}%+"
                 fi
                 ;;
             -)
                 # For relative dB operations, vol is already the target percentage
                 if [ "$is_relative_db" = "true" ]; then
                     wpctl set-volume "$NODE_ID" "${vol}%"
                 else
                     wpctl set-volume "$NODE_ID" "${vol}%-"
                 fi
                 ;;
             *) wpctl set-volume "$NODE_ID" "${vol}%" ;;
         esac

         # Log successful volume change
         if not_empty "${LOG_FILE:-}"; then
             local new_vol
             new_vol=$(get_volume 2>/dev/null || echo "0")
             log_info "Volume changed successfully" "node: $(get_sink_nick 2>/dev/null || echo "sink $NODE_ID")" "from: ${current_vol}%" "to: ${new_vol}%"
         fi
     fi
 }

increase_volume() {
     local step=${1:-}
     if empty "$step"; then
         step=$(get_effective_default_step)
     fi
     set_volume "$step" "+"
 }
decrease_volume() {
     local step=${1:-}
     if empty "$step"; then
         step=$(get_effective_default_step)
     fi
     set_volume "$step" "-"
 }

wheel_volume() {
     local -r delta_change=${1:?$(error 'Wheel delta is required')}
     local step threshold current_delta new_delta volume_change threshold_reached

     # Use DEFAULT_STEP as the base for threshold (per-sink or global)
     step=$(get_effective_default_step)
     # Threshold is based on step size - accumulate until we reach one step
     threshold=$(awk "BEGIN {printf \"%.2f\", $step}")

     # Get current accumulated delta
     current_delta=$(get_wheel_delta)

     # Add the new change to accumulated delta
     new_delta=$(awk "BEGIN {printf \"%.2f\", $current_delta + $delta_change}")

     # Check if we've reached the threshold
     threshold_reached=$(awk "BEGIN {if ($new_delta >= $threshold || $new_delta <= -$threshold) print 1; else print 0}")
     if (( threshold_reached == 1 )); then
         # Calculate how many whole steps to apply
         volume_change=$(awk "BEGIN {printf \"%.0f\", $new_delta}")

         # Apply the volume change
         if (( volume_change > 0 )); then
             increase_volume "$volume_change"
         elif (( volume_change < 0 )); then
             decrease_volume "${volume_change#-}"  # Remove negative sign
         fi

         # Reset accumulated delta (keep remainder)
         new_delta=$(awk "BEGIN {printf \"%.2f\", $new_delta - $volume_change}")
     fi

     # Save the new accumulated delta
     save_wheel_delta "$new_delta"
 }

toggle_mute() {
     # Check if operating on all sinks
     if $ALL_SINKS; then
         toggle_mute_all
         return
     fi

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         local node_display
         node_display=$(get_node_display_name 2>/dev/null || echo "sink $NODE_ID")
         local currently_muted
         currently_muted=$(is_muted && echo "muted" || echo "unmuted")
         local new_state
         new_state=$([ "$currently_muted" = "muted" ] && echo "unmuted" || echo "muted")
         local current_vol
         current_vol=$(get_volume 2>/dev/null || echo "0")
         dry_run_msg "Would toggle mute on $node_display"
         dry_run_msg "  Current state: $currently_muted"
         dry_run_msg "  New state: $new_state"
         dry_run_msg "  Current volume: ${current_vol}%"
         if not_empty "$FADE_DURATION"; then
             if [ "$currently_muted" = "muted" ]; then
                 dry_run_msg "  Would fade in from 0% to ${current_vol}% over ${FADE_DURATION}ms"
             else
                 dry_run_msg "  Would fade out from ${current_vol}% to 0% over ${FADE_DURATION}ms, then mute"
             fi
         fi
         return 0
     fi

     if not_empty "$FADE_DURATION"; then
         if is_muted; then
             # Fade in (unmute)
             wpctl set-mute "$NODE_ID" 0
             local current_vol saved_vol
             current_vol=$(get_volume)
             # Try to restore saved volume from before mute
             saved_vol=$(restore_volume_after_mute)
             if not_empty "$saved_vol"; then
                 # Restore to saved volume
                 wpctl set-volume "$NODE_ID" "0%"
                 fade_volume "$saved_vol" "$FADE_DURATION" "$NODE_ID"
                 clear_saved_volume
             elif (( current_vol == 0 )); then
                 # If volume is 0, fade from 0 to a reasonable level
                 fade_volume "${DEFAULT_VOL:-50}" "$FADE_DURATION" "$NODE_ID"
             else
                 # Fade from 0 to current volume
                 wpctl set-volume "$NODE_ID" "0%"
                 fade_volume "$current_vol" "$FADE_DURATION" "$NODE_ID"
             fi
         else
             # Fade out (mute)
             # Ensure device is not muted before starting fade
             wpctl set-mute "$NODE_ID" 0 &>/dev/null
             # Invalidate cache to ensure we get the current volume
             invalidate_cache
             local current_vol
             current_vol=$(get_volume)
             # Save the current volume before muting so we can restore it later
             save_volume_before_mute "$current_vol"
             # Fade down to 0 from current volume
             # Pass current_vol as starting volume to ensure we fade from the correct value
             fade_volume 0 "$FADE_DURATION" "$NODE_ID" "$current_vol"
             # Now that fade is complete, mute the device
             # Set volume to 0 one more time to ensure it's at 0, then mute
             wpctl set-volume "$NODE_ID" "0%" &>/dev/null
             wpctl set-mute "$NODE_ID" 1
             # Some systems restore volume when muting, so set it to 0 again after mute
             wpctl set-volume "$NODE_ID" "0%" &>/dev/null
             invalidate_cache
         fi
     else
         invalidate_cache
         wpctl set-mute "$NODE_ID" toggle
     fi

     # Log successful mute toggle
     if not_empty "${LOG_FILE:-}" && [[ "${DRY_RUN:-false}" != "true" ]]; then
         local node_display
         node_display=$(get_node_display_name 2>/dev/null || echo "sink $NODE_ID")
         local new_state
         new_state=$(is_muted && echo "muted" || echo "unmuted")
         log_info "Mute toggled successfully" "node: $node_display" "state: $new_state"
     fi
 }

set_mic_volume() {
     local -r vol=${1:?$(error 'Volume is required')}
     local -r op=${2:-}

     if empty "$SOURCE_ID"; then
         init_source
     fi

     if empty "$SOURCE_ID"; then
         error_with_suggestion "No audio source available." \
             "Check if a microphone or audio input device is connected." \
             "Use 'volume list sources' to see available sources."
         return 1
     fi

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         local source_display
         source_display=$(get_source_nick 2>/dev/null || echo "source $SOURCE_ID")
         local current_mic_vol
         current_mic_vol=$(get_mic_volume 2>/dev/null || echo "0")
         local target_vol
         case "$op" in
             +) target_vol=$(decimal_add "$current_mic_vol" "$vol") ;;
             -) target_vol=$(decimal_subtract "$current_mic_vol" "$vol") ;;
             *) target_vol="$vol" ;;
         esac
         dry_run_msg "Would set microphone volume on $source_display"
         dry_run_msg "  Current volume: ${current_mic_vol}%"
         if [ "$op" = "+" ]; then
             dry_run_msg "  Operation: increase by ${vol}%"
         elif [ "$op" = "-" ]; then
             dry_run_msg "  Operation: decrease by ${vol}%"
         else
             dry_run_msg "  Operation: set to ${vol}%"
         fi
         dry_run_msg "  Target volume: ${target_vol}%"
         return 0
     fi

     invalidate_cache

     case "$op" in
         +) wpctl set-volume "$SOURCE_ID" "${vol}%+" ;;
         -) wpctl set-volume "$SOURCE_ID" "${vol}%-" ;;
         *) wpctl set-volume "$SOURCE_ID" "${vol}%" ;;
     esac
 }

increase_mic_volume() {
     local step=${1:-}
     if empty "$step"; then
         step=${DEFAULT_STEP:-5}
     fi
     set_mic_volume "$step" "+"
 }
decrease_mic_volume() {
     local step=${1:-}
     if empty "$step"; then
         step=${DEFAULT_STEP:-5}
     fi
     set_mic_volume "$step" "-"
 }
toggle_mic_mute() {
     if empty "$SOURCE_ID"; then
         init_source
     fi

     if empty "$SOURCE_ID"; then
         error_with_suggestion "No audio source available." \
             "Check if a microphone or audio input device is connected." \
             "Use 'volume list sources' to see available sources."
         return 1
     fi

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         local source_display
         source_display=$(get_source_nick 2>/dev/null || echo "source $SOURCE_ID")
         local currently_muted
         currently_muted=$(is_mic_muted && echo "muted" || echo "unmuted")
         local new_state
         new_state=$([ "$currently_muted" = "muted" ] && echo "unmuted" || echo "muted")
         local current_mic_vol
         current_mic_vol=$(get_mic_volume 2>/dev/null || echo "0")
         dry_run_msg "Would toggle microphone mute on $source_display"
         dry_run_msg "  Current state: $currently_muted"
         dry_run_msg "  New state: $new_state"
         dry_run_msg "  Current volume: ${current_mic_vol}%"
         return 0
     fi

     invalidate_cache
     wpctl set-mute "$SOURCE_ID" toggle
 }

show_mic_notification() {
     $DISPLAY_NOTIFICATIONS || return

     if empty "$NOTIFICATION_METHOD"; then
         load_notify_server_info
         NOTIFICATION_METHOD=$NOTIFY_SERVER
     fi

     setup_notification_icons
     notify_mic
 }

 # Output format plugin wrappers (use generalized plugin system from define_helpers)
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
     # List built-in formats
     awk 'match($0,/ +output_volume_([[:alnum:]]+)\(\)/) {print substr($0, RSTART + 18, RLENGTH - 20)}' "${BASH_SOURCE[0]}" || EXITCODE=$EX_USAGE
     # List output plugins
     list_output_plugins
 }

list_sinks() {
     local default_sink_name
     default_sink_name=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '/[ \*]+node\.name/{gsub(/"/, "", $4); print $4}')

     local sinks
     readarray -t sinks < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink") | "\(.id)|\(.info.props."node.name")|\(.info.props."node.nick" // "N/A")"' 2>/dev/null)

     if [[ ${#sinks[@]} -eq 0 ]]; then
         error "No audio sinks found."
         return 1
     fi

     echo "${COLOR_YELLOW}Audio Sinks:${COLOR_RESET}"
     echo

     local sink_id sink_name sink_nick vol muted is_default
     for sink in "${sinks[@]}"; do
         IFS='|' read -r sink_id sink_name sink_nick <<< "$sink"

         # Get volume and mute status
         vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
         muted=$(wpctl get-volume "$sink_id" 2>/dev/null | grep -q '\[MUTED\]' && echo "MUTED" || echo "")

         # Check if this is the default sink
         if [[ "$sink_name" == "$default_sink_name" ]]; then
             is_default="${COLOR_GREEN}*${COLOR_RESET} "
         else
             is_default="  "
         fi

         # Apply alias if available
         local display_name="$sink_nick"
         if isset NODE_ALIASES["$sink_id"]; then
             display_name="${NODE_ALIASES[$sink_id]}"
         elif isset NODE_ALIASES["$sink_name"]; then
             display_name="${NODE_ALIASES[$sink_name]}"
         elif isset NODE_ALIASES["$sink_nick"]; then
             display_name="${NODE_ALIASES[$sink_nick]}"
         fi

         printf "%s${COLOR_CYAN}%3s${COLOR_RESET}  ${COLOR_GREEN}%s${COLOR_RESET}" "$is_default" "$sink_id" "$display_name"
         if [[ -n "$muted" ]]; then
             printf "  ${COLOR_RED}[MUTED]${COLOR_RESET}  ${COLOR_YELLOW}%3s%%${COLOR_RESET}" "$vol"
         else
             printf "  ${COLOR_YELLOW}%3s%%${COLOR_RESET}" "$vol"
         fi
         echo "  ${COLOR_MAGENTA}($sink_name)${COLOR_RESET}"
     done
     echo
     echo "${COLOR_GREEN}*${COLOR_RESET} = default sink"
 }

list_sources() {
     local default_source_name
     default_source_name=$(wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '/[ \*]+node\.name/{gsub(/"/, "", $4); print $4}')

     local sources
     readarray -t sources < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Source") | "\(.id)|\(.info.props."node.name")|\(.info.props."node.nick" // "N/A")"' 2>/dev/null)

     if [[ ${#sources[@]} -eq 0 ]]; then
         error_with_suggestion "No audio sources found." \
             "Check if a microphone or audio input device is connected." \
             "Ensure PipeWire is running: systemctl --user status pipewire pipewire-pulse"
         return 1
     fi

     echo "${COLOR_YELLOW}Audio Sources:${COLOR_RESET}"
     echo

     local source_id source_name source_nick vol muted is_default
     for source in "${sources[@]}"; do
         IFS='|' read -r source_id source_name source_nick <<< "$source"

         # Get volume and mute status
         vol=$(wpctl get-volume "$source_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
         muted=$(wpctl get-volume "$source_id" 2>/dev/null | grep -q '\[MUTED\]' && echo "MUTED" || echo "")

         # Check if this is the default source
         if [[ "$source_name" == "$default_source_name" ]]; then
             is_default="${COLOR_GREEN}*${COLOR_RESET} "
         else
             is_default="  "
         fi

         # Apply alias if available
         local display_name="$source_nick"
         if isset NODE_ALIASES["$source_id"]; then
             display_name="${NODE_ALIASES[$source_id]}"
         elif isset NODE_ALIASES["$source_name"]; then
             display_name="${NODE_ALIASES[$source_name]}"
         elif isset NODE_ALIASES["$source_nick"]; then
             display_name="${NODE_ALIASES[$source_nick]}"
         fi

         printf "%s${COLOR_CYAN}%3s${COLOR_RESET}  ${COLOR_GREEN}%s${COLOR_RESET}" "$is_default" "$source_id" "$display_name"
         if [[ -n "$muted" ]]; then
             printf "  ${COLOR_RED}[MUTED]${COLOR_RESET}  ${COLOR_YELLOW}%3s%%${COLOR_RESET}" "$vol"
         else
             printf "  ${COLOR_YELLOW}%3s%%${COLOR_RESET}" "$vol"
         fi
         echo "  ${COLOR_MAGENTA}($source_name)${COLOR_RESET}"
     done
     echo
     echo "${COLOR_GREEN}*${COLOR_RESET} = default source"
 }

list_ports() {
     if empty "$NODE_ID"; then
         error_with_suggestion "No sink specified. Use -s <sink> or ensure default sink is available." \
             "Use 'volume list sinks' to see available sinks." \
             "Specify a sink with: volume -s <sink_name> port list"
         if [[ "${VERBOSE:-false}" == "true" ]]; then
             local diag
             diag=$(get_pipewire_diagnostics)
             if not_empty "$diag"; then
                 echo "${COLOR_CYAN}[verbose]${COLOR_RESET} $diag" >&2
             fi
         fi
         return 1
     fi

     local sink_display_name
     sink_display_name=$(get_node_display_name)

     echo "${COLOR_YELLOW}Ports for sink: ${COLOR_GREEN}$sink_display_name${COLOR_RESET} (ID: ${COLOR_CYAN}$NODE_ID${COLOR_RESET})"
     echo

     # Try to get ports from PropInfo first with availability
     local ports
     readarray -t ports < <(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .values[]? | "\(.id)|\(.name)|\(.description // "N/A")|\(.availability // "unknown")"' 2>/dev/null)

     # If no ports found via PropInfo, try alternative method using node properties
     if [[ ${#ports[@]} -eq 0 ]]; then
         readarray -t ports < <(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.props | to_entries[] | select(.key | test("port\\..*")) | "\(.key)|\(.value)|N/A|unknown"' 2>/dev/null)
     fi

     if [[ ${#ports[@]} -eq 0 ]]; then
         echo "${COLOR_YELLOW}No ports found for this sink.${COLOR_RESET}"
         echo "This sink may not support port switching, or port information is not available."
         echo "Try using ${COLOR_GREEN}wpctl status${COLOR_RESET} for more information."
         return 0
     fi

     # Get active port
     local active_port
     active_port=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .value' 2>/dev/null)

     # If no active port from PropInfo, try node properties
     if empty "$active_port"; then
         active_port=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.props."audio.port" // empty' 2>/dev/null)
     fi

     local port_id port_name port_desc port_availability is_active availability_status
     for port in "${ports[@]}"; do
         IFS='|' read -r port_id port_name port_desc port_availability <<< "$port"

         # Handle different port formats
         if [[ -z "$port_desc" || "$port_desc" == "N/A" ]]; then
             port_desc="$port_name"
         fi

         # Determine if port is active
         if [[ "$port_id" == "$active_port" || "$port_name" == "$active_port" ]]; then
             is_active="${COLOR_GREEN}*${COLOR_RESET} "
         else
             is_active="  "
         fi

         # Format availability status
         case "$port_availability" in
             available|yes|1|true)
                 availability_status="${COLOR_GREEN}[plugged]${COLOR_RESET}"
                 ;;
             unavailable|no|0|false)
                 availability_status="${COLOR_RED}[unplugged]${COLOR_RESET}"
                 ;;
             *)
                 # If availability is unknown, try to check it
                 local checked_availability
                 checked_availability=$(get_port_availability "$port_id" 2>/dev/null || echo "unknown")
                 case "$checked_availability" in
                     available)
                         availability_status="${COLOR_GREEN}[plugged]${COLOR_RESET}"
                         ;;
                     unavailable)
                         availability_status="${COLOR_RED}[unplugged]${COLOR_RESET}"
                         ;;
                     *)
                         availability_status="${COLOR_YELLOW}[unknown]${COLOR_RESET}"
                         ;;
                 esac
                 ;;
         esac

         printf "%s${COLOR_CYAN}%s${COLOR_RESET}  ${COLOR_GREEN}%s${COLOR_RESET}  %s" "$is_active" "$port_id" "$port_desc" "$availability_status"
         if [[ -n "$port_name" && "$port_name" != "$port_desc" ]]; then
             echo "  ${COLOR_MAGENTA}($port_name)${COLOR_RESET}"
         else
             echo
         fi
     done
     echo
     echo "${COLOR_GREEN}*${COLOR_RESET} = active port"
 }

list() {
     local -r type=${1:-}

     case "$type" in
         sinks|sink)
             list_sinks
             ;;
         sources|source)
             list_sources
             ;;
         ports|port)
             list_ports
             ;;
         "")
             error "List type required. Use: list sinks|sources|ports"
             echo "  ${COLOR_GREEN}list sinks${COLOR_RESET}    - list all audio output sinks"
             echo "  ${COLOR_GREEN}list sources${COLOR_RESET} - list all audio input sources"
             echo "  ${COLOR_GREEN}list ports${COLOR_RESET}    - list ports for current sink"
             EXITCODE=$EX_USAGE
             return 1
             ;;
         *)
             error "Unknown list type: $type"
             echo "Valid types: sinks, sources, ports"
             EXITCODE=$EX_USAGE
             return 1
             ;;
     esac
 }

get_active_port_description() {
     if empty "$NODE_ID"; then
         return 1
     fi

     # Get active port ID - try multiple methods
     local active_port_id
     active_port_id=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .value' 2>/dev/null)

     # Fallback: try node properties
     if empty "$active_port_id"; then
         active_port_id=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.props."audio.port" // empty' 2>/dev/null)
     fi

     if empty "$active_port_id"; then
         return 1
     fi

     # Get port description - try multiple methods
     local port_desc
     port_desc=$(pw_dump | jq -r --argjson node_id "$NODE_ID" --arg port_id "$active_port_id" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .values[]? | select(.id == $port_id) | .description // .name' 2>/dev/null)

     # Fallback: try to get from port name if description not available
     if empty "$port_desc"; then
         port_desc=$(pw_dump | jq -r --argjson node_id "$NODE_ID" --arg port_id "$active_port_id" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .values[]? | select(.id == $port_id) | .name' 2>/dev/null)
     fi

     # If still empty, use port_id as fallback
     if empty "$port_desc"; then
         port_desc="$active_port_id"
     fi

     echo "$port_desc"
 }

get_port_availability() {
     local -r port_id=$1
     if empty "$NODE_ID" || empty "$port_id"; then
         return 1
     fi

     # Check port availability from PropInfo
     local availability
     availability=$(pw_dump | jq -r --argjson node_id "$NODE_ID" --arg port_id "$port_id" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .values[]? | select(.id == $port_id) | .availability // "unknown"' 2>/dev/null)

     # If availability is not in PropInfo, try to infer from port properties
     if [[ "$availability" == "unknown" || -z "$availability" ]]; then
         # Check if port exists in available ports list (if it's listed, it's likely available)
         local port_exists
         port_exists=$(pw_dump | jq -r --argjson node_id "$NODE_ID" --arg port_id "$port_id" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .values[]? | select(.id == $port_id) | .id' 2>/dev/null)
         if [[ -n "$port_exists" ]]; then
             availability="available"
         else
             availability="unavailable"
         fi
     fi

     echo "$availability"
 }

get_all_ports() {
     if empty "$NODE_ID"; then
         return 1
     fi

     # Get all ports for the current sink with availability information
     # Format: port_id|port_name|port_description|availability
     local ports
     readarray -t ports < <(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .values[]? | "\(.id)|\(.name)|\(.description // "N/A")|\(.availability // "unknown")"' 2>/dev/null)

     if [[ ${#ports[@]} -eq 0 ]]; then
         return 1
     fi

     echo "${ports[@]}"
 }

check_for_newly_available_ports() {
     if empty "$NODE_ID"; then
         return 1
     fi

     # Get current active port
     local current_port
     current_port=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .value' 2>/dev/null)

     # Get all available ports
     local -a all_ports
     readarray -t all_ports < <(get_all_ports)

     if [[ ${#all_ports[@]} -eq 0 ]]; then
         return 1
     fi

     # Find newly available ports (available but not currently active)
     local port_id port_name port_desc port_availability
     local -a newly_available_ports
     for port in "${all_ports[@]}"; do
         IFS='|' read -r port_id port_name port_desc port_availability <<< "$port"

         # Check if port is available and not the current one
         if [[ "$port_id" != "$current_port" ]]; then
             # Check availability
             local availability
             availability=$(get_port_availability "$port_id" 2>/dev/null || echo "unknown")
             if [[ "$availability" == "available" ]] || [[ "$port_availability" == "available" ]]; then
                 # Format: port_id|port_description
                 newly_available_ports+=("$port_id|$port_desc")
             fi
         fi
     done

     # If we found newly available ports, suggest switching
     if [[ ${#newly_available_ports[@]} -gt 0 ]]; then
         # Return the first newly available port (most likely the one just plugged in)
         echo "${newly_available_ports[0]}"
         return 0
     fi

     return 1
 }

detect_and_suggest_port_switch() {
     if empty "$NODE_ID" || ! $DISPLAY_NOTIFICATIONS; then
         return 0
     fi

     # Check for newly available ports
     local new_port_info
     new_port_info=$(check_for_newly_available_ports 2>/dev/null)

     if not_empty "$new_port_info"; then
         IFS='|' read -r new_port_id new_port_desc <<< "$new_port_info"

         # Only suggest if we have a meaningful description
         if not_empty "$new_port_desc" && [[ "$new_port_desc" != "N/A" ]]; then
             local icon summary body
             icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[1]}" || echo "${ICONS_SYMBOLIC[1]}")

             # Include sink name if multiple sinks available
             local sink_info=""
             if has_multiple_sinks; then
                 local sink_display_name
                 sink_display_name=$(get_node_display_name)
                 sink_info=" on $sink_display_name"
             fi

             summary="New port available: $new_port_desc${sink_info}"
             body="Switch with: volume port set $new_port_id"

             case "$NOTIFICATION_METHOD" in
                 libnotify|dunst|notify-osd)
                     notify_volume_libnotify 0 "$icon" "$summary" "$body"
                     ;;
                 *)
                     if is_notification_plugin_available "$NOTIFICATION_METHOD"; then
                         call_notification_plugin "$NOTIFICATION_METHOD" 0 "$icon" "$summary" "$body" || notify_volume_libnotify 0 "$icon" "$summary" "$body"
                     else
                         notify_volume_libnotify 0 "$icon" "$summary" "$body"
                     fi
                     ;;
             esac
         fi
     fi
 }

find_port_by_name_or_id() {
     local -r search=$1
     local port_id port_name port_desc

     if empty "$NODE_ID"; then
         return 1
     fi

     # Get all ports
     local -a all_ports
     readarray -t all_ports < <(get_all_ports)

     if [[ ${#all_ports[@]} -eq 0 ]]; then
         return 1
     fi

     # Search for port
     for port in "${all_ports[@]}"; do
         IFS='|' read -r port_id port_name port_desc <<< "$port"

         # Try as ID
         if [[ "$port_id" == "$search" ]]; then
             echo "$port_id"
             return 0
         fi

         # Try as name
         if [[ "$port_name" == "$search" ]]; then
             echo "$port_id"
             return 0
         fi

         # Try as description (case-insensitive partial match)
         if [[ "${port_desc,,}" == *"${search,,}"* ]]; then
             echo "$port_id"
             return 0
         fi
     done

     return 1
 }

set_port() {
     local -r port_target=${1:?$(error 'Port name or ID is required')}

     if empty "$NODE_ID"; then
         error "No sink specified. Use -s <sink> or ensure default sink is available."
         return 1
     fi

     # Find the port
     local port_id
     port_id=$(find_port_by_name_or_id "$port_target")

     if empty "$port_id"; then
         error_with_suggestion "Port not found: $port_target" \
             "Use 'volume port list' to see available ports for the current sink." \
             "Port names are case-sensitive."
         return 1
     fi

     # Get current active port
     local current_port
     current_port=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .value' 2>/dev/null)

     if [[ "$port_id" == "$current_port" ]]; then
         echo "Port is already active."
         return 0
     fi

     # Set the port using pw-cli set-param
     # Note: This requires the EnumPort param to be available on the node
     # The param format uses PipeWire's POD format for Props
     # To test port switching on a device with ports:
     #   1. Use 'volume port list' to see available ports
     #   2. Use 'volume port set <port_id>' to switch ports
     #   3. Verify with 'wpctl inspect <node_id>' that the port changed
     if ! pw-cli set-param "$NODE_ID" Props '{"EnumPort":"'"$port_id"'"}' &>/dev/null; then
         error_with_suggestion "Failed to set port to $port_id" \
             "The port may not be available for this sink." \
             "Use 'volume port list' to verify the port exists and is available."
         echo "Note: Port switching may not be supported on this device, or the port ID may be incorrect."
         echo "Verify ports are available with: volume port list"
         return 1
     fi

     # Get port description for notification
     local port_desc
     port_desc=$(pw_dump | jq -r --argjson node_id "$NODE_ID" --arg port_id "$port_id" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .values[]? | select(.id == $port_id) | .description // .name' 2>/dev/null)

     # Invalidate cache
     invalidate_cache

     # Show notification if enabled
     if $DISPLAY_NOTIFICATIONS; then
         local icon summary body=""
         icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[1]}" || echo "${ICONS_SYMBOLIC[1]}")

         # Include sink name if multiple sinks available
         local sink_info=""
         if has_multiple_sinks; then
             local sink_display_name
             sink_display_name=$(get_node_display_name)
             sink_info=" on $sink_display_name"
         fi

         summary="Port switched to: $port_desc${sink_info}"

         case "$NOTIFICATION_METHOD" in
             libnotify|dunst|notify-osd)
                 notify_volume_libnotify 0 "$icon" "$summary" "$body"
                 ;;
             *)
                 if is_notification_plugin_available "$NOTIFICATION_METHOD"; then
                     call_notification_plugin "$NOTIFICATION_METHOD" 0 "$icon" "$summary" "$body" || notify_volume_libnotify 0 "$icon" "$summary" "$body"
                 else
                     notify_volume_libnotify 0 "$icon" "$summary" "$body"
                 fi
                 ;;
         esac
     else
         echo "Port switched to: $port_desc"
     fi

     # Update statusbar if configured
     update_statusbar || true
 }

port() {
     local -r subcommand=${1:-}
     local -r target=${2:-}

     case "$subcommand" in
         list)
             list_ports
             ;;
         set)
             if empty "$target"; then
                 error "Port name or ID required. Use: port set <port>"
                 echo "Use 'volume port list' to see available ports."
                 EXITCODE=$EX_USAGE
                 return 1
             fi
             set_port "$target"
             ;;
         "")
             error "Port subcommand required. Use: port list|set"
             echo "  ${COLOR_GREEN}port list${COLOR_RESET}        - list available ports"
             echo "  ${COLOR_GREEN}port set <port>${COLOR_RESET}  - set active port"
             EXITCODE=$EX_USAGE
             return 1
             ;;
         *)
             error "Unknown port subcommand: $subcommand"
             echo "Valid subcommands: list, set"
             EXITCODE=$EX_USAGE
             return 1
             ;;
     esac
 }

get_profiles_dir() {
     echo "${XDG_CONFIG_HOME:-$HOME/.config}/i3-volume/profiles"
 }

get_config_dir() {
     echo "${XDG_CONFIG_HOME:-$HOME/.config}/i3-volume"
 }

get_port_cache_file() {
     local config_dir
     config_dir=$(get_config_dir)
     echo "$config_dir/.last_port_${NODE_ID:-default}"
 }

save_last_port() {
     local -r port_id=$1
     if empty "$port_id"; then
         return 1
     fi

     local port_file
     port_file=$(get_port_cache_file)
     local config_dir
     config_dir=$(get_config_dir)

     # Create config directory if it doesn't exist
     mkdir -p "$config_dir" || {
         return 1
     }

     # Save the port ID to file
     echo "$port_id" > "$port_file" 2>/dev/null || {
         return 1
     }
 }

get_last_port() {
     local port_file
     port_file=$(get_port_cache_file)

     if [[ ! -f "$port_file" ]]; then
         return 1
     fi

     cat "$port_file" 2>/dev/null
 }

save_volume_before_mute() {
     local -r vol=$1
     local config_dir volume_file
     config_dir=$(get_config_dir)
     volume_file="$config_dir/.volume_before_mute"

     # Create config directory if it doesn't exist
     mkdir -p "$config_dir" || {
         error "Failed to create config directory: $config_dir"
         return 1
     }

     # Save the volume to file
     echo "$vol" > "$volume_file" || {
         error "Failed to save volume to: $volume_file"
         return 1
     }
 }

restore_volume_after_mute() {
     local config_dir volume_file
     config_dir=$(get_config_dir)
     volume_file="$config_dir/.volume_before_mute"

     # Check if the file exists
     if [[ ! -f "$volume_file" ]]; then
         return 1
     fi

     # Read the saved volume
     local saved_vol
     saved_vol=$(cat "$volume_file" 2>/dev/null)

     # Validate the volume
     if empty "$saved_vol" || ! [[ "$saved_vol" =~ ^[0-9]+$ ]]; then
         rm -f "$volume_file"
         return 1
     fi

     # Return the saved volume
     echo "$saved_vol"
 }

clear_saved_volume() {
     local config_dir volume_file
     config_dir=$(get_config_dir)
     volume_file="$config_dir/.volume_before_mute"
     rm -f "$volume_file"
 }

get_wheel_delta_file() {
     local config_dir
     config_dir=$(get_config_dir)
     echo "$config_dir/.wheel_delta"
 }

get_wheel_delta() {
     local delta_file
     delta_file=$(get_wheel_delta_file)

     if [[ ! -f "$delta_file" ]]; then
         echo "0"
         return
     fi

     local delta
     delta=$(cat "$delta_file" 2>/dev/null)

     if empty "$delta" || ! [[ "$delta" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
         echo "0"
         return
     fi

     echo "$delta"
 }

save_wheel_delta() {
     local -r delta=$1
     local config_dir delta_file
     config_dir=$(get_config_dir)
     delta_file=$(get_wheel_delta_file)

     # Create config directory if it doesn't exist
     mkdir -p "$config_dir" || {
         error "Failed to create config directory: $config_dir"
         return 1
     }

     # Save the delta to file
     echo "$delta" > "$delta_file" || {
         error "Failed to save wheel delta to: $delta_file"
         return 1
     }
 }

get_boost_file() {
     local config_dir
     config_dir=$(get_config_dir)
     echo "$config_dir/.volume_boost"
 }

get_boost_pid_file() {
     local config_dir
     config_dir=$(get_config_dir)
     echo "$config_dir/.volume_boost_pid"
 }

save_boost_state() {
     local -r original_vol=$1
     local -r boost_amount=$2
     local -r timeout_sec=$3
     local boost_file
     boost_file=$(get_boost_file)

     # Create config directory if it doesn't exist
     local config_dir
     config_dir=$(get_config_dir)
     mkdir -p "$config_dir" || {
         error "Failed to create config directory: $config_dir"
         return 1
     }

     # Save boost state: original_vol|boost_amount|timeout_sec|timestamp
     echo "${original_vol}|${boost_amount}|${timeout_sec}|$(date +%s)" > "$boost_file" || {
         error "Failed to save boost state"
         return 1
     }
 }

get_boost_state() {
     local boost_file
     boost_file=$(get_boost_file)

     if [[ ! -f "$boost_file" ]]; then
         return 1
     fi

     # Read boost state
     local boost_data
     boost_data=$(cat "$boost_file" 2>/dev/null)

     if empty "$boost_data"; then
         return 1
     fi

     # Parse: original_vol|boost_amount|timeout_sec|timestamp
     IFS='|' read -r BOOST_ORIGINAL_VOL BOOST_AMOUNT BOOST_TIMEOUT BOOST_TIMESTAMP <<< "$boost_data"

     # Validate
     if empty "$BOOST_ORIGINAL_VOL" || empty "$BOOST_AMOUNT" || empty "$BOOST_TIMEOUT" || empty "$BOOST_TIMESTAMP"; then
         return 1
     fi

     # Check if boost has expired
     local current_time elapsed_time
     current_time=$(date +%s)
     elapsed_time=$(( current_time - BOOST_TIMESTAMP ))

     if (( elapsed_time >= BOOST_TIMEOUT )); then
         # Boost has expired, clean up
         clear_boost_state
         return 1
     fi

     return 0
 }

clear_boost_state() {
     local boost_file pid_file
     boost_file=$(get_boost_file)
     pid_file=$(get_boost_pid_file)

     # Kill background process if it exists
     if [[ -f "$pid_file" ]]; then
         local pid
         pid=$(cat "$pid_file" 2>/dev/null)
         if not_empty "$pid" && kill -0 "$pid" 2>/dev/null; then
             kill "$pid" 2>/dev/null || true
         fi
         rm -f "$pid_file"
     fi

     rm -f "$boost_file"
 }

is_boost_active() {
     get_boost_state 2>/dev/null
 }

enable_boost() {
     local -r boost_amount=${1:?$(error 'Boost amount is required')}
     local -r timeout_sec=${2:-30}  # Default 30 seconds
     local current_vol original_vol target_vol actual_boost

     # Validate boost amount
     if ! [[ "$boost_amount" =~ ^[0-9]+$ ]] || (( boost_amount < 1 || boost_amount > 100 )); then
         error "Invalid boost amount: $boost_amount (must be 1-100)"
         return 1
     fi

     # Check if boost is already active
     if is_boost_active; then
         error "Boost is already active. Use 'volume boost off' to cancel first."
         return 1
     fi

     # Get current volume
     current_vol=$(get_volume)
     original_vol=$current_vol

     # Calculate target volume (boost is additive percentage)
     target_vol=$(( current_vol + boost_amount ))
     actual_boost=$boost_amount

     # Respect MAX_VOL if set (per-sink or global)
     local effective_max_vol
     effective_max_vol=$(get_effective_max_vol)
     if not_empty "$effective_max_vol" && (( target_vol > effective_max_vol )); then
         target_vol=$effective_max_vol
         # Adjust boost amount to what we can actually apply
         actual_boost=$(( target_vol - original_vol ))
         if (( actual_boost <= 0 )); then
             error "Cannot boost: already at maximum volume"
             return 1
         fi
     fi

     # Don't exceed 200% (hard limit for safety)
     if (( target_vol > 200 )); then
         target_vol=200
         actual_boost=$(( target_vol - original_vol ))
     fi

     # Save boost state (use actual_boost for what was actually applied)
     save_boost_state "$original_vol" "$actual_boost" "$timeout_sec" || return 1

     # Set boosted volume
     if not_empty "$FADE_DURATION"; then
         fade_volume "$target_vol" "$FADE_DURATION" "$NODE_ID"
     else
         invalidate_cache
         wpctl set-volume "$NODE_ID" "${target_vol}%"
     fi

     # Start background process to auto-revert
     # Capture values needed in subshell
     local config_dir_boost node_id_boost
     config_dir_boost=$(get_config_dir)
     node_id_boost=$NODE_ID
     (
         sleep "$timeout_sec"
         # Check if boost is still active (might have been cancelled)
         local boost_file restore_vol
         boost_file="$config_dir_boost/.volume_boost"
         if [[ -f "$boost_file" ]]; then
             # Read original volume from file
             local boost_data
             boost_data=$(cat "$boost_file" 2>/dev/null)
             if [[ -n "$boost_data" ]]; then
                 IFS='|' read -r restore_vol _ _ _ <<< "$boost_data"
                 # Restore original volume (direct wpctl call, no fade in background)
                 if [[ -n "$restore_vol" ]]; then
                     wpctl set-volume "$node_id_boost" "${restore_vol}%" &>/dev/null
                 fi
                 # Clean up boost state files
                 rm -f "$boost_file"
                 rm -f "$config_dir_boost/.volume_boost_pid"
             fi
         fi
     ) &

     # Save PID of background process
     local pid_file
     pid_file=$(get_boost_pid_file)
     echo $! > "$pid_file"

     if [[ "$actual_boost" != "$boost_amount" ]]; then
         echo "Boost enabled: +${actual_boost}% (requested +${boost_amount}%, limited by max volume) for ${timeout_sec}s"
     else
         echo "Boost enabled: +${actual_boost}% for ${timeout_sec}s"
     fi
 }

disable_boost() {
     if ! is_boost_active; then
         error "No active boost to cancel"
         return 1
     fi

     # Get original volume
     local original_vol
     original_vol=$BOOST_ORIGINAL_VOL

     # Restore original volume
     if not_empty "$FADE_DURATION"; then
         fade_volume "$original_vol" "$FADE_DURATION" "$NODE_ID"
     else
         invalidate_cache
         wpctl set-volume "$NODE_ID" "${original_vol}%"
     fi

     # Clear boost state (this also kills the background process)
     clear_boost_state

     echo "Boost disabled"
 }

boost() {
     local -r subcommand=${1:-}
     local -r value=${2:-}

     case "$subcommand" in
         off|cancel|disable)
             disable_boost
             ;;
         "")
             error "Boost subcommand required. Use: boost <amount> [timeout] or boost off"
             echo "  ${COLOR_GREEN}boost <amount> [timeout]${COLOR_RESET}  - enable boost (default timeout: 30s)"
             echo "  ${COLOR_GREEN}boost off${COLOR_RESET}                 - disable boost"
             EXITCODE=$EX_USAGE
             return 1
             ;;
         *)
             # Try to parse as boost amount
             if [[ "$subcommand" =~ ^[0-9]+$ ]]; then
                 enable_boost "$subcommand" "$value"
             else
                 error "Unknown boost subcommand: $subcommand"
                 echo "Use: boost <amount> [timeout] or boost off"
                 EXITCODE=$EX_USAGE
                 return 1
             fi
             ;;
     esac
 }

save_profile() {
     local -r profile_name=${1:?$(error 'Profile name is required')}
     local profiles_dir profile_file

     # Validate profile name (alphanumeric, dash, underscore only)
     if [[ ! "$profile_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
         error "Invalid profile name: $profile_name"
         echo "Profile names can only contain letters, numbers, dashes, and underscores."
         return 1
     fi

     profiles_dir=$(get_profiles_dir)
     profile_file="$profiles_dir/$profile_name.json"

     # Create profiles directory if it doesn't exist
     mkdir -p "$profiles_dir" || {
         error "Failed to create profiles directory: $profiles_dir"
         return 1
     }

     # Get current state
     local vol muted sink_name port_id mic_vol mic_muted
     vol=$(get_volume)
     muted=$(is_muted && echo "true" || echo "false")
     sink_name="$NODE_NAME"
     port_id=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.PropInfo[]? | select(.id == "EnumPort") | .value' 2>/dev/null || echo "")

     # Get mic state if available
     if not_empty "$SOURCE_ID"; then
         mic_vol=$(get_mic_volume 2>/dev/null || echo "")
         mic_muted=$(is_mic_muted 2>/dev/null && echo "true" || echo "false")
     else
         mic_vol=""
         mic_muted=""
     fi

     # Create JSON profile
     local profile_json
     profile_json=$(jq -n \
         --arg vol "$vol" \
         --arg muted "$muted" \
         --arg sink "$sink_name" \
         --arg port "$port_id" \
         --arg mic_vol "${mic_vol:-}" \
         --arg mic_muted "${mic_muted:-}" \
         '{volume: ($vol | tonumber), muted: ($muted == "true"), sink: $sink, port: (if $port == "" then null else $port end), mic_volume: (if $mic_vol == "" then null else ($mic_vol | tonumber) end), mic_muted: (if $mic_muted == "" then null else ($mic_muted == "true") end)}' 2>/dev/null)

     if empty "$profile_json"; then
         error "Failed to create profile JSON"
         return 1
     fi

     # Save to file
     echo "$profile_json" > "$profile_file" || {
         error "Failed to save profile to: $profile_file"
         return 1
     }

     echo "Profile saved: $profile_name"
     if $DISPLAY_NOTIFICATIONS; then
         local icon summary
         icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[1]}" || echo "${ICONS_SYMBOLIC[1]}")
         summary="Profile saved: $profile_name"

         case "$NOTIFICATION_METHOD" in
             libnotify|dunst|notify-osd)
                 notify_volume_libnotify 0 "$icon" "$summary" ""
                 ;;
             *)
                 if is_notification_plugin_available "$NOTIFICATION_METHOD"; then
                     call_notification_plugin "$NOTIFICATION_METHOD" 0 "$icon" "$summary" "" || notify_volume_libnotify 0 "$icon" "$summary" ""
                 else
                     notify_volume_libnotify 0 "$icon" "$summary" ""
                 fi
                 ;;
         esac
     fi
 }

load_profile() {
     local -r profile_name=${1:?$(error 'Profile name is required')}
     local profiles_dir profile_file

     profiles_dir=$(get_profiles_dir)
     profile_file="$profiles_dir/$profile_name.json"

     if [[ ! -f "$profile_file" ]]; then
         error_with_suggestion "Profile not found: $profile_name" \
             "Use 'volume profile list' to see available profiles." \
             "Create a profile with: volume profile save <name>"
         return 1
     fi

     # Read profile JSON
     local vol muted sink_name port_id mic_vol mic_muted
     vol=$(jq -r '.volume // empty' "$profile_file" 2>/dev/null)
     muted=$(jq -r '.muted // false' "$profile_file" 2>/dev/null)
     sink_name=$(jq -r '.sink // empty' "$profile_file" 2>/dev/null)
     port_id=$(jq -r '.port // empty' "$profile_file" 2>/dev/null)
     mic_vol=$(jq -r '.mic_volume // empty' "$profile_file" 2>/dev/null)
     mic_muted=$(jq -r '.mic_muted // false' "$profile_file" 2>/dev/null)

     if empty "$vol"; then
         error "Invalid profile: $profile_name (missing volume)"
         return 1
     fi

     # Switch sink if specified and different
     if not_empty "$sink_name" && [[ "$sink_name" != "$NODE_NAME" ]]; then
         # Find sink by name
         local sink_id
         sink_id=$(pw_dump | jq -r --arg name "$sink_name" '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink" and .info.props."node.name" == $name) | .id' 2>/dev/null)

         if not_empty "$sink_id"; then
             wpctl set-default "$sink_id" &>/dev/null
             invalidate_cache
             # Reinitialize audio to get new NODE_ID
             NODE_NAME="$sink_name"
             NODE_ID=$(get_node_id)
         fi
     fi

     # Set volume
     set_volume "$vol"

     # Set mute status
     local current_muted
     current_muted=$(is_muted && echo "true" || echo "false")
     if [[ "$muted" == "true" && "$current_muted" != "true" ]]; then
         toggle_mute
     elif [[ "$muted" != "true" && "$current_muted" == "true" ]]; then
         toggle_mute
     fi

     # Set port if specified
     if not_empty "$port_id" && [[ "$port_id" != "null" ]]; then
         set_port "$port_id" &>/dev/null || true
     fi

     # Set mic volume and mute if specified
     if not_empty "$mic_vol" && [[ "$mic_vol" != "null" ]] && not_empty "$SOURCE_ID"; then
         set_mic_volume "$mic_vol"
         local current_mic_muted
         current_mic_muted=$(is_mic_muted 2>/dev/null && echo "true" || echo "false")
         if [[ "$mic_muted" == "true" && "$current_mic_muted" != "true" ]]; then
             toggle_mic_mute
         elif [[ "$mic_muted" != "true" && "$current_mic_muted" == "true" ]]; then
             toggle_mic_mute
         fi
     fi

     echo "Profile loaded: $profile_name"
     if $DISPLAY_NOTIFICATIONS; then
         local icon summary
         icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[1]}" || echo "${ICONS_SYMBOLIC[1]}")
         summary="Profile loaded: $profile_name"

         case "$NOTIFICATION_METHOD" in
             libnotify|dunst|notify-osd)
                 notify_volume_libnotify "$vol" "$icon" "$summary" ""
                 ;;
             *)
                 if is_notification_plugin_available "$NOTIFICATION_METHOD"; then
                     call_notification_plugin "$NOTIFICATION_METHOD" "$vol" "$icon" "$summary" "" || notify_volume_libnotify "$vol" "$icon" "$summary" ""
                 else
                     notify_volume_libnotify "$vol" "$icon" "$summary" ""
                 fi
                 ;;
         esac
     fi

     # Update statusbar
     update_statusbar || true
 }

list_profiles() {
     local profiles_dir
     profiles_dir=$(get_profiles_dir)

     if [[ ! -d "$profiles_dir" ]]; then
         echo "${COLOR_YELLOW}No profiles directory found.${COLOR_RESET}"
         echo "Save a profile first using: ${COLOR_GREEN}volume profile save <name>${COLOR_RESET}"
         return 0
     fi

     local profiles
     readarray -t profiles < <(find "$profiles_dir" -name "*.json" -type f -printf "%f\n" 2>/dev/null | sed 's/\.json$//' | sort)

     if [[ ${#profiles[@]} -eq 0 ]]; then
         echo "${COLOR_YELLOW}No profiles found.${COLOR_RESET}"
         echo "Save a profile first using: ${COLOR_GREEN}volume profile save <name>${COLOR_RESET}"
         return 0
     fi

     echo "${COLOR_YELLOW}Saved Profiles:${COLOR_RESET}"
     echo

     local profile_name profile_file vol muted sink_name
     for profile_name in "${profiles[@]}"; do
         profile_file="$profiles_dir/$profile_name.json"
         vol=$(jq -r '.volume // "N/A"' "$profile_file" 2>/dev/null)
         muted=$(jq -r '.muted // false' "$profile_file" 2>/dev/null)
         sink_name=$(jq -r '.sink // "default"' "$profile_file" 2>/dev/null)

         printf "  ${COLOR_GREEN}%s${COLOR_RESET}" "$profile_name"
         if [[ "$muted" == "true" ]]; then
             printf "  ${COLOR_RED}[MUTED]${COLOR_RESET}  ${COLOR_YELLOW}%s%%${COLOR_RESET}" "$vol"
         else
             printf "  ${COLOR_YELLOW}%s%%${COLOR_RESET}" "$vol"
         fi
         echo "  ${COLOR_MAGENTA}($sink_name)${COLOR_RESET}"
     done
     echo
 }

delete_profile() {
     local -r profile_name=${1:?$(error 'Profile name is required')}
     local profiles_dir profile_file

     profiles_dir=$(get_profiles_dir)
     profile_file="$profiles_dir/$profile_name.json"

     if [[ ! -f "$profile_file" ]]; then
         error_with_suggestion "Profile not found: $profile_name" \
             "Use 'volume profile list' to see available profiles." \
             "Create a profile with: volume profile save <name>"
         return 1
     fi

     rm -f "$profile_file" || {
         error "Failed to delete profile: $profile_name"
         return 1
     }

     echo "Profile deleted: $profile_name"
 }

profile() {
     local -r subcommand=${1:-}
     local -r target=${2:-}

     case "$subcommand" in
         save)
             if empty "$target"; then
                 error "Profile name required. Use: profile save <name>"
                 EXITCODE=$EX_USAGE
                 return 1
             fi
             save_profile "$target"
             ;;
         load)
             if empty "$target"; then
                 error "Profile name required. Use: profile load <name>"
                 EXITCODE=$EX_USAGE
                 return 1
             fi
             load_profile "$target"
             ;;
         list)
             list_profiles
             ;;
         delete|remove|rm)
             if empty "$target"; then
                 error "Profile name required. Use: profile delete <name>"
                 EXITCODE=$EX_USAGE
                 return 1
             fi
             delete_profile "$target"
             ;;
         "")
             error "Profile subcommand required. Use: profile save|load|list|delete"
             echo "  ${COLOR_GREEN}profile save <name>${COLOR_RESET}   - save current settings as profile"
             echo "  ${COLOR_GREEN}profile load <name>${COLOR_RESET}   - load a saved profile"
             echo "  ${COLOR_GREEN}profile list${COLOR_RESET}          - list all saved profiles"
             echo "  ${COLOR_GREEN}profile delete <name>${COLOR_RESET} - delete a profile"
             EXITCODE=$EX_USAGE
             return 1
             ;;
         *)
             # Quick access: profile <name> loads the profile
             load_profile "$subcommand"
             ;;
     esac
 }

get_config_file() {
     echo "${XDG_CONFIG_HOME:-$HOME/.config}/i3-volume/config"
 }

show_config() {
     local config_file
     config_file=$(get_config_file)

     if [[ ! -f "$config_file" ]]; then
         echo "${COLOR_YELLOW}No configuration file found.${COLOR_RESET}"
         echo "Config file location: ${COLOR_CYAN}$config_file${COLOR_RESET}"
         echo ""
         echo "Create a config file to customize i3-volume behavior."
         echo "Use ${COLOR_GREEN}volume config validate${COLOR_RESET} to check config syntax."
         return 0
     fi

     echo "${COLOR_YELLOW}Current Configuration:${COLOR_RESET}"
     echo "Config file: ${COLOR_CYAN}$config_file${COLOR_RESET}"
     echo ""

     # Show all config variables with their current values
     local line_num=0
     while IFS= read -r line || [[ -n "$line" ]]; do
         ((line_num++))
         local trimmed_line
         trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

         # Skip empty lines and comments
         [[ -z "$trimmed_line" ]] && continue
         [[ "$trimmed_line" =~ ^# ]] && continue

         # Check for include directive
         if [[ "$trimmed_line" =~ ^source[[:space:]]+ ]] || [[ "$trimmed_line" =~ ^\.[[:space:]]+ ]]; then
             local include_file
             include_file=$(echo "$trimmed_line" | sed -E 's/^(source|\.)[[:space:]]+["'\'']?([^"'\'']+)["'\'']?.*/\2/')
             printf "  ${COLOR_MAGENTA}%s${COLOR_RESET} ${COLOR_CYAN}(include: %s)${COLOR_RESET}\n" "$trimmed_line" "$include_file"
             continue
         fi

         # Extract variable name and value
         if [[ "$trimmed_line" =~ ^([A-Z_][A-Z0-9_]*(\[.*\])?)=(.*)$ ]]; then
             local var_name="${BASH_REMATCH[1]}"
             local var_value="${BASH_REMATCH[3]}"

             # Remove quotes if present
             var_value=$(echo "$var_value" | sed "s/^[\"']//;s/[\"']$//")

             # Get current value from environment (try to evaluate safely)
             local current_value="<not set>"
             if [[ "$var_name" =~ \[ ]]; then
                 # Array variable - show as-is
                 current_value="$var_value"
             else
                 # Regular variable - try to get from environment
                 local var_ref="${var_name}"
                 if [[ -n "${!var_ref:-}" ]]; then
                     current_value="${!var_ref}"
                 else
                     current_value="$var_value ${COLOR_MAGENTA}(from config, not yet loaded)${COLOR_RESET}"
                 fi
             fi

             printf "  ${COLOR_CYAN}%s${COLOR_RESET} = ${COLOR_GREEN}%s${COLOR_RESET}\n" "$var_name" "$current_value"
         fi
     done < "$config_file"

     echo ""
     echo "Use ${COLOR_GREEN}volume config validate${COLOR_RESET} to check config syntax."
     echo "Use ${COLOR_GREEN}volume config docs${COLOR_RESET} to see all configurable variables."
 }

validate_config() {
     local config_file
     config_file=$(get_config_file)

     if [[ ! -f "$config_file" ]]; then
         echo "${COLOR_YELLOW}No configuration file found.${COLOR_RESET}"
         echo "Config file location: ${COLOR_CYAN}$config_file${COLOR_RESET}"
         return 0
     fi

     echo "${COLOR_YELLOW}Validating configuration file:${COLOR_RESET} ${COLOR_CYAN}$config_file${COLOR_RESET}"
     echo ""

     local errors=0
     local line_num=0

     while IFS= read -r line || [[ -n "$line" ]]; do
         ((line_num++))
         local trimmed_line
         trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

         # Skip empty lines and comments
         [[ -z "$trimmed_line" ]] && continue
         [[ "$trimmed_line" =~ ^# ]] && continue

         # Check for include directive
         if [[ "$trimmed_line" =~ ^source[[:space:]]+ ]] || [[ "$trimmed_line" =~ ^\.[[:space:]]+ ]]; then
             local include_file
             include_file=$(echo "$trimmed_line" | sed -E 's/^(source|\.)[[:space:]]+["'\'']?([^"'\'']+)["'\'']?.*/\2/')
             if [[ ! -f "$include_file" ]]; then
                 # Try relative to config directory
                 local config_dir
                 config_dir=$(get_config_dir)
                 if [[ ! -f "$config_dir/$include_file" ]]; then
                     echo "${COLOR_RED}Error on line $line_num:${COLOR_RESET} Include file not found: ${COLOR_CYAN}$include_file${COLOR_RESET}"
                     ((errors++))
                 fi
             fi
             continue
         fi

         # Check for valid variable assignment
         if [[ ! "$trimmed_line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
             # Check if it's an array assignment
             if [[ "$trimmed_line" =~ ^[A-Z_][A-Z0-9_]*\[.*\]= ]]; then
                 # Valid array assignment
                 continue
             else
                 echo "${COLOR_RED}Error on line $line_num:${COLOR_RESET} Invalid syntax: ${COLOR_CYAN}$trimmed_line${COLOR_RESET}"
                 echo "  Expected format: VARIABLE_NAME=value or VARIABLE_NAME[key]=value"
                 ((errors++))
             fi
         fi
     done < "$config_file"

     # Try to source the config to check for syntax errors
     if (( errors == 0 )); then
         # Use a subshell to avoid affecting current environment
         if ! (bash -n "$config_file" 2>&1); then
             echo "${COLOR_RED}Syntax errors found when parsing config file:${COLOR_RESET}"
             bash -n "$config_file" 2>&1 | while IFS= read -r err_line; do
                 echo "  $err_line"
             done
             ((errors++))
         fi
     fi

     if (( errors == 0 )); then
         echo "${COLOR_GREEN}✓ Configuration file is valid${COLOR_RESET}"
         return 0
     else
         echo ""
         echo "${COLOR_RED}✗ Found $errors error(s)${COLOR_RESET}"
         return 1
     fi
 }

show_config_docs() {
     cat <<- EOF
${COLOR_YELLOW}i3-volume Configuration Variables${COLOR_RESET}

Configuration file location: ${COLOR_CYAN}~/.config/i3-volume/config${COLOR_RESET} or ${COLOR_CYAN}\$XDG_CONFIG_HOME/i3-volume/config${COLOR_RESET}

${COLOR_YELLOW}Notification Settings:${COLOR_RESET}
  ${COLOR_CYAN}NOTIFICATION_METHOD${COLOR_RESET}
 Notification method to use (default: libnotify)
 Options: libnotify, dunst, xosd, herbe, volnoti, kosd

  ${COLOR_CYAN}DISPLAY_NOTIFICATIONS${COLOR_RESET}
 Enable/disable notifications (default: false)
 Values: true, false

  ${COLOR_CYAN}USE_DUNSTIFY${COLOR_RESET}
 Use dunstify instead of notify-send (default: false)
 Values: true, false

  ${COLOR_CYAN}USE_FULLCOLOR_ICONS${COLOR_RESET}
 Use full-color icons instead of symbolic (default: false)
 Values: true, false

  ${COLOR_CYAN}SHOW_VOLUME_PROGRESS${COLOR_RESET}
 Show progress bar in notifications (default: false)
 Values: true, false

  ${COLOR_CYAN}PROGRESS_PLACEMENT${COLOR_RESET}
 Where to place progress bar (default: summary)
 Options: summary, body

  ${COLOR_CYAN}EXPIRES${COLOR_RESET}
 Notification expiration time in milliseconds (default: 1500)
 Values: integer (milliseconds)

  ${COLOR_CYAN}SYMBOLIC_ICON_SUFFIX${COLOR_RESET}
 Suffix to add to symbolic icon names
 Values: string

  ${COLOR_CYAN}NOTIFICATION_GROUP${COLOR_RESET}
 Group volume change notifications (dunst only) (default: false)
 Values: true, false

${COLOR_YELLOW}Volume Control Settings:${COLOR_RESET}
  ${COLOR_CYAN}DEFAULT_STEP${COLOR_RESET}
 Default step size for volume changes (default: 5)
 Values: integer (percentage)

  ${COLOR_CYAN}MAX_VOL${COLOR_RESET}
 Maximum volume limit (optional)
 Values: integer (percentage, 0-200)

${COLOR_YELLOW}Per-Sink Configuration:${COLOR_RESET}
  Per-sink settings allow you to configure different values for different audio devices.
  Settings can be keyed by sink ID, name, or nick. Per-sink settings take precedence
  over global settings.

  ${COLOR_CYAN}SINK_MAX_VOL[sink_identifier]${COLOR_RESET}
 Per-sink maximum volume limit
 Examples:
   SINK_MAX_VOL[alsa_output.pci-0000_00_1f.3.analog-stereo]=100
   SINK_MAX_VOL[USB Audio]=120
   SINK_MAX_VOL[headphones]=150

  ${COLOR_CYAN}SINK_DEFAULT_STEP[sink_identifier]${COLOR_RESET}
 Per-sink default step size for volume changes
 Examples:
   SINK_DEFAULT_STEP[alsa_output.pci-0000_00_1f.3.analog-stereo]=5
   SINK_DEFAULT_STEP[USB Audio]=10
   SINK_DEFAULT_STEP[headphones]=2

  ${COLOR_CYAN}SINK_DISPLAY_NOTIFICATIONS[sink_identifier]${COLOR_RESET}
 Per-sink notification display preference
 Examples:
   SINK_DISPLAY_NOTIFICATIONS[headphones]=true
   SINK_DISPLAY_NOTIFICATIONS[speakers]=false

  Note: Per-sink settings are automatically applied when the sink changes.

  ${COLOR_CYAN}FADE_DURATION${COLOR_RESET}
 Fade duration in milliseconds for volume changes (optional)
 Values: integer (milliseconds)

${COLOR_YELLOW}Status Bar Settings:${COLOR_RESET}
  ${COLOR_CYAN}STATUSLINE${COLOR_RESET}
 Status bar process name (e.g., i3blocks)
 Values: string

  ${COLOR_CYAN}SIGNAL${COLOR_RESET}
 Signal to send to status bar (requires STATUSLINE)
 Values: string (e.g., SIGRTMIN+10)

${COLOR_YELLOW}Audio Device Settings:${COLOR_RESET}
  ${COLOR_CYAN}NODE_NAME${COLOR_RESET}
 Default sink name (optional)
 Values: string

  ${COLOR_CYAN}SOURCE_NAME${COLOR_RESET}
 Default source name (optional)
 Values: string

  ${COLOR_CYAN}NODE_ALIASES${COLOR_RESET}
 Aliases for node names (associative array)
 Example: NODE_ALIASES[ALC287 Analog]="Speakers"

  ${COLOR_CYAN}PORT_ALIASES${COLOR_RESET}
 Aliases for port names (associative array)
 Example: PORT_ALIASES[analog-output-speaker]="Speaker"

${COLOR_YELLOW}Sound Settings:${COLOR_RESET}
  ${COLOR_CYAN}PLAY_SOUND${COLOR_RESET}
 Play sound for volume changes (default: false)
 Values: true, false

  ${COLOR_CYAN}USE_CANBERRA${COLOR_RESET}
 Use libcanberra for sound playback (default: false)
 Values: true, false

${COLOR_YELLOW}Other Settings:${COLOR_RESET}
  ${COLOR_CYAN}ALL_SINKS${COLOR_RESET}
 Operate on all sinks (default: false)
 Values: true, false

  ${COLOR_CYAN}VERBOSE${COLOR_RESET}
 Enable verbose mode (default: false)
 Values: true, false

${COLOR_YELLOW}Config File Includes:${COLOR_RESET}
  You can include other config files using:
 source /path/to/other/config
 . /path/to/other/config

  Paths can be relative to the config directory or absolute.

${COLOR_YELLOW}Example Configuration:${COLOR_RESET}
  See example configs in: ${COLOR_CYAN}~/.config/i3-volume/examples/${COLOR_RESET}

EOF
 }

config() {
     local -r subcommand=${1:-}
     local -r target=${2:-}

     case "$subcommand" in
         show|list|"")
             show_config
             ;;
         validate|check)
             validate_config
             ;;
         docs|help|variables)
             show_config_docs
             ;;
         *)
             error "Unknown config subcommand: $subcommand"
             echo "Valid subcommands:"
             echo "  ${COLOR_GREEN}config${COLOR_RESET}              - show current configuration"
             echo "  ${COLOR_GREEN}config validate${COLOR_RESET}    - validate config file syntax"
             echo "  ${COLOR_GREEN}config docs${COLOR_RESET}         - show all configurable variables"
             EXITCODE=$EX_USAGE
             return 1
             ;;
     esac
 }

get_all_sinks() {
     # Returns array of sink IDs
     local sinks
     readarray -t sinks < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink") | .id' 2>/dev/null)
     echo "${sinks[@]}"
 }

get_all_sources() {
     # Returns array of source IDs
     local sources
     readarray -t sources < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Source") | .id' 2>/dev/null)
     echo "${sources[@]}"
 }

set_volume_all() {
     local -r vol_input=$1
     local -r op=${2:-}
     local -a all_sinks
     readarray -t all_sinks < <(get_all_sinks)

     if [[ ${#all_sinks[@]} -eq 0 ]]; then
         error_with_suggestion "No audio sinks found." \
             "Check if PipeWire is running: systemctl --user status pipewire pipewire-pulse" \
             "Ensure audio devices are connected and recognized by the system."
         if [[ "${VERBOSE:-false}" == "true" ]]; then
             local diag
             diag=$(get_pipewire_diagnostics)
             if not_empty "$diag"; then
                 echo "${COLOR_CYAN}[verbose]${COLOR_RESET} $diag" >&2
             fi
         fi
         return 1
     fi

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         dry_run_msg "Would set volume on all ${#all_sinks[@]} sink(s)"
         local sink_id
         for sink_id in "${all_sinks[@]}"; do
             local sink_name
             sink_name=$(pw_dump | jq -r --argjson id "$sink_id" '.[] | select(.id == $id) | .info.props."node.nick" // .info.props."node.name" // "Unknown"' 2>/dev/null)
             local current_vol
             current_vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.2f", $2 * 100}' || echo "0")
             dry_run_msg "  Sink: $sink_name (ID: $sink_id) - Current: ${current_vol}%"
         done
         dry_run_msg "  Operation: ${op:-set} ${vol_input}"
         return 0
     fi

     # Detect if input is in dB or percentage, and convert to percentage for internal use
     local vol vol_unit
     vol_unit=$(detect_volume_unit "$vol_input")
     if [ "$vol_unit" = "db" ]; then
         # For relative operations with dB, we need special handling per sink
         if [ "$op" = "+" ] || [ "$op" = "-" ]; then
             # Will handle per-sink in the loop
             vol="$vol_input"
         else
             # Absolute dB value: convert to percentage
             vol=$(parse_volume_value "$vol_input")
         fi
     else
         # Already in percentage
         vol="$vol_input"
     fi

     local sink_id
     for sink_id in "${all_sinks[@]}"; do
         local target_vol current_vol vol_to_use
         local effective_max_vol
         effective_max_vol=$(get_effective_max_vol "$sink_id")

         # Handle relative dB operations per sink
         if [ "$vol_unit" = "db" ] && ([ "$op" = "+" ] || [ "$op" = "-" ]); then
             current_vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.2f", $2 * 100}')
             local current_db new_db
             current_db=$(percentage_to_db "$current_vol")
             # Extract numeric part from dB input (remove "dB", "db", "DB", or "Db" suffix)
             local db_value
             if [[ "$vol_input" =~ ^(.+)[dD][bB]$ ]]; then
                 db_value="${BASH_REMATCH[1]}"
             else
                 db_value="$vol_input"
             fi
             if [ "$op" = "+" ]; then
                 new_db=$(decimal_add "$current_db" "$db_value")
             else
                 new_db=$(decimal_subtract "$current_db" "$db_value")
             fi
             vol_to_use=$(db_to_percentage "$new_db")
         else
             vol_to_use="$vol"
         fi

         if not_empty "$effective_max_vol"; then
             case "$op" in
                 +)  # Increase volume
                     if [ "$vol_unit" != "db" ]; then
                         current_vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.2f", $2 * 100}')
                         local sum_vol
                         sum_vol=$(decimal_add "$current_vol" "$vol_to_use")
                         if [ "$(decimal_gt "$sum_vol" "$effective_max_vol")" = "1" ]; then
                             local step
                             step=$(decimal_subtract "$effective_max_vol" "$current_vol")
                             if [ "$(decimal_lt "$step" "0")" = "1" ]; then
                                 step="0"
                             fi
                             local step_int
                             step_int=$(printf "%.0f" "$step")
                             if not_empty "$FADE_DURATION"; then
                                 fade_volume "$effective_max_vol" "$FADE_DURATION" "$sink_id"
                             else
                                 wpctl set-volume "$sink_id" "${step_int}%+"
                             fi
                             continue
                         fi
                     fi
                     ;;
                 *)  # Set absolute volume
                     if [ "$(decimal_gt "$vol_to_use" "$effective_max_vol")" = "1" ]; then
                         continue
                     fi
                     ;;
             esac
         fi

         # Handle fade if requested
         if not_empty "$FADE_DURATION"; then
             case "$op" in
                 +)
                     if [ "$vol_unit" != "db" ]; then
                         current_vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.2f", $2 * 100}')
                         target_vol=$(decimal_add "$current_vol" "$vol_to_use")
                     else
                         target_vol="$vol_to_use"
                     fi
                     fade_volume "$target_vol" "$FADE_DURATION" "$sink_id"
                     ;;
                 -)
                     if [ "$vol_unit" != "db" ]; then
                         current_vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.2f", $2 * 100}')
                         target_vol=$(decimal_subtract "$current_vol" "$vol_to_use")
                     else
                         target_vol="$vol_to_use"
                     fi
                     fade_volume "$target_vol" "$FADE_DURATION" "$sink_id"
                     ;;
                 *)
                     fade_volume "$vol_to_use" "$FADE_DURATION" "$sink_id"
                     ;;
             esac
         else
             case "$op" in
                 +) wpctl set-volume "$sink_id" "${vol_to_use}%+" ;;
                 -) wpctl set-volume "$sink_id" "${vol_to_use}%-" ;;
                 *) wpctl set-volume "$sink_id" "${vol_to_use}%" ;;
             esac
         fi
     done

     invalidate_cache
 }

toggle_mute_all() {
     local -a all_sinks
     readarray -t all_sinks < <(get_all_sinks)

     if [[ ${#all_sinks[@]} -eq 0 ]]; then
         error_with_suggestion "No audio sinks found." \
             "Check if PipeWire is running: systemctl --user status pipewire pipewire-pulse" \
             "Ensure audio devices are connected and recognized by the system."
         if [[ "${VERBOSE:-false}" == "true" ]]; then
             local diag
             diag=$(get_pipewire_diagnostics)
             if not_empty "$diag"; then
                 echo "${COLOR_CYAN}[verbose]${COLOR_RESET} $diag" >&2
             fi
         fi
         return 1
     fi

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         dry_run_msg "Would toggle mute on all ${#all_sinks[@]} sink(s)"
         local sink_id
         for sink_id in "${all_sinks[@]}"; do
             local sink_name
             sink_name=$(pw_dump | jq -r --argjson id "$sink_id" '.[] | select(.id == $id) | .info.props."node.nick" // .info.props."node.name" // "Unknown"' 2>/dev/null)
             local is_muted
             is_muted=$(wpctl get-volume "$sink_id" 2>/dev/null | grep -q '\[MUTED\]' && echo "muted" || echo "unmuted")
             local new_state
             new_state=$([ "$is_muted" = "muted" ] && echo "unmuted" || echo "muted")
             dry_run_msg "  Sink: $sink_name (ID: $sink_id) - $is_muted → $new_state"
         done
         return 0
     fi

     local sink_id
     for sink_id in "${all_sinks[@]}"; do
         local is_muted
         is_muted=$(wpctl get-volume "$sink_id" 2>/dev/null | grep -q '\[MUTED\]' && echo true || echo false)

         if not_empty "$FADE_DURATION"; then
             if $is_muted; then
                 # Fade in (unmute)
                 wpctl set-mute "$sink_id" 0
                 local current_vol
                 current_vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
                 if (( current_vol == 0 )); then
                     fade_volume "${DEFAULT_VOL:-50}" "$FADE_DURATION" "$sink_id"
                 else
                     wpctl set-volume "$sink_id" "0%"
                     fade_volume "$current_vol" "$FADE_DURATION" "$sink_id"
                 fi
             else
                 # Fade out (mute)
                 wpctl set-mute "$sink_id" 0 &>/dev/null
                 local current_vol
                 current_vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
                 fade_volume 0 "$FADE_DURATION" "$sink_id" "$current_vol"
                 wpctl set-volume "$sink_id" "0%" &>/dev/null
                 wpctl set-mute "$sink_id" 1
                 wpctl set-volume "$sink_id" "0%" &>/dev/null
             fi
         else
             wpctl set-mute "$sink_id" toggle
         fi
     done

     invalidate_cache
 }

sync_volume() {
     # Get volume from default sink and sync to all other sinks
     local -a all_sinks
     readarray -t all_sinks < <(get_all_sinks)

     if [[ ${#all_sinks[@]} -eq 0 ]]; then
         error_with_suggestion "No audio sinks found." \
             "Check if PipeWire is running: systemctl --user status pipewire pipewire-pulse" \
             "Ensure audio devices are connected and recognized by the system."
         if [[ "${VERBOSE:-false}" == "true" ]]; then
             local diag
             diag=$(get_pipewire_diagnostics)
             if not_empty "$diag"; then
                 echo "${COLOR_CYAN}[verbose]${COLOR_RESET} $diag" >&2
             fi
         fi
         return 1
     fi

     if [[ ${#all_sinks[@]} -eq 1 ]]; then
         echo "Only one sink available. Nothing to sync."
         return 0
     fi

     # Get volume and mute status from default sink
     local default_sink_id
     default_sink_id=$(get_default_sink_id)

     if empty "$default_sink_id"; then
         error_with_suggestion "Could not determine default sink." \
             "Check if PipeWire is running: systemctl --user status pipewire pipewire-pulse" \
             "Use 'volume list sinks' to see available sinks." \
             "Set a default sink manually if needed."
         if [[ "${VERBOSE:-false}" == "true" ]]; then
             local diag
             diag=$(get_pipewire_diagnostics)
             if not_empty "$diag"; then
                 echo "${COLOR_CYAN}[verbose]${COLOR_RESET} $diag" >&2
             fi
         fi
         return 1
     fi

     local target_vol target_muted
     target_vol=$(wpctl get-volume "$default_sink_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
     target_muted=$(wpctl get-volume "$default_sink_id" 2>/dev/null | grep -q '\[MUTED\]' && echo true || echo false)

     # Sync to all sinks
     local sink_id synced_count=0
     for sink_id in "${all_sinks[@]}"; do
         # Skip the default sink (already at target)
         if [[ "$sink_id" == "$default_sink_id" ]]; then
             continue
         fi

         # Set volume
         if not_empty "$FADE_DURATION"; then
             fade_volume "$target_vol" "$FADE_DURATION" "$sink_id"
         else
             wpctl set-volume "$sink_id" "${target_vol}%"
         fi

         # Set mute status
         local current_muted
         current_muted=$(wpctl get-volume "$sink_id" 2>/dev/null | grep -q '\[MUTED\]' && echo true || echo false)
         if [[ "$target_muted" == "true" && "$current_muted" != "true" ]]; then
             wpctl set-mute "$sink_id" 1
         elif [[ "$target_muted" != "true" && "$current_muted" == "true" ]]; then
             wpctl set-mute "$sink_id" 0
         fi

         ((synced_count++))
     done

     invalidate_cache

     if (( synced_count > 0 )); then
         local mute_text=""
         if $target_muted; then
             mute_text=" (MUTED)"
         fi
         echo "Synced volume to $synced_count sink(s): ${target_vol}%${mute_text}"
     else
         echo "All sinks already synchronized."
     fi
 }

get_default_sink_id() {
     # Returns the ID of the current default sink
     local default_sink_name
     default_sink_name=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '/[ \*]+node\.name/{gsub(/"/, "", $4); print $4}')
     pw_dump | jq -r --arg name "$default_sink_name" '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."node.name" == $name) | .id' 2>/dev/null
 }

get_sink_display_name_by_id() {
     local -r sink_id=$1
     local sink_name sink_nick display_name

     sink_name=$(pw_dump | jq -r --argjson id "$sink_id" '.[] | select(.id == $id) | .info.props."node.name"' 2>/dev/null)
     sink_nick=$(pw_dump | jq -r --argjson id "$sink_id" '.[] | select(.id == $id) | .info.props."node.nick" // "N/A"' 2>/dev/null)

     # Apply alias if available
     display_name="$sink_nick"
     if isset NODE_ALIASES["$sink_id"]; then
         display_name="${NODE_ALIASES[$sink_id]}"
     elif isset NODE_ALIASES["$sink_name"]; then
         display_name="${NODE_ALIASES[$sink_name]}"
     elif isset NODE_ALIASES["$sink_nick"]; then
         display_name="${NODE_ALIASES[$sink_nick]}"
     fi

     echo "$display_name"
 }

find_sink_by_name_or_id() {
     # Find sink by ID, name, nick, or alias
     local -r search=$1
     local sink_id sink_name sink_nick

     # Try as ID first
     sink_id=$(pw_dump | jq -r --argjson id "$search" '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink" and .id == ($id | tonumber? // empty)) | .id' 2>/dev/null)

     if not_empty "$sink_id"; then
         echo "$sink_id"
         return 0
     fi

     # Try as name
     sink_id=$(pw_dump | jq -r --arg name "$search" '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink" and .info.props."node.name" == $name) | .id' 2>/dev/null)

     if not_empty "$sink_id"; then
         echo "$sink_id"
         return 0
     fi

     # Try as nick
     sink_id=$(pw_dump | jq -r --arg nick "$search" '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink" and .info.props."node.nick" == $nick) | .id' 2>/dev/null)

     if not_empty "$sink_id"; then
         echo "$sink_id"
         return 0
     fi

     # Try as alias
     local alias_key
     for alias_key in "${!NODE_ALIASES[@]}"; do
         if [[ "${NODE_ALIASES[$alias_key]}" == "$search" ]]; then
             # Found alias, now find the sink
             sink_id=$(pw_dump | jq -r --arg key "$alias_key" '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink" and (.id == ($key | tonumber? // empty) or .info.props."node.name" == $key or .info.props."node.nick" == $key)) | .id' 2>/dev/null)
             if not_empty "$sink_id"; then
                 echo "$sink_id"
                 return 0
             fi
         fi
     done

     return 1
 }

switch_sink() {
     local target_sink_id target_sink_name
     local -r target=${1:-}

     # Get all available sinks
     local -a all_sinks
     readarray -t all_sinks < <(get_all_sinks)

     if [[ ${#all_sinks[@]} -eq 0 ]]; then
         error_with_suggestion "No audio sinks found." \
             "Check if PipeWire is running: systemctl --user status pipewire pipewire-pulse" \
             "Ensure audio devices are connected and recognized by the system."
         if [[ "${VERBOSE:-false}" == "true" ]]; then
             local diag
             diag=$(get_pipewire_diagnostics)
             if not_empty "$diag"; then
                 echo "${COLOR_CYAN}[verbose]${COLOR_RESET} $diag" >&2
             fi
         fi
         return 1
     fi

     if [[ ${#all_sinks[@]} -eq 1 ]]; then
         error "Only one sink available. Nothing to switch to."
         return 1
     fi

     # If no target specified, cycle to next sink
     if empty "$target"; then
         local current_sink_id
         current_sink_id=$(get_default_sink_id)

         if empty "$current_sink_id"; then
             error "Could not determine current default sink."
             return 1
         fi

         # Find current sink index
         local idx=0
         local found=false
         for sink in "${all_sinks[@]}"; do
             if [[ "$sink" == "$current_sink_id" ]]; then
                 found=true
                 break
             fi
             ((idx++))
         done

         if ! $found; then
             error "Current sink not found in available sinks."
             return 1
         fi

         # Move to next sink (wrap around)
         idx=$(( (idx + 1) % ${#all_sinks[@]} ))
         target_sink_id="${all_sinks[$idx]}"
     else
         # Find sink by name, ID, or alias
         target_sink_id=$(find_sink_by_name_or_id "$target")

         if empty "$target_sink_id"; then
             error_with_suggestion "Sink not found: $target" \
                 "Use 'volume list sinks' to see available sinks." \
                 "You can use sink ID, name, or nick to switch sinks."
             if [[ "${VERBOSE:-false}" == "true" ]]; then
                 echo "${COLOR_CYAN}[verbose]${COLOR_RESET} Searched for: $target" >&2
                 local available_sinks
                 available_sinks=$(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Sink") | "\(.id)|\(.info.props."node.name")|\(.info.props."node.nick" // "N/A")"' 2>/dev/null | head -5)
                 if not_empty "$available_sinks"; then
                     echo "${COLOR_CYAN}[verbose]${COLOR_RESET} Available sinks:" >&2
                     echo "$available_sinks" | while IFS='|' read -r id name nick; do
                         echo "${COLOR_CYAN}[verbose]${COLOR_RESET}   ID: $id, Name: $name, Nick: $nick" >&2
                     done
                 fi
             fi
             return 1
         fi

         # Check if it's already the default
         local current_sink_id
         current_sink_id=$(get_default_sink_id)
         if [[ "$target_sink_id" == "$current_sink_id" ]]; then
             echo "Sink is already the default."
             return 0
         fi
     fi

     # Get target sink name for display
     target_sink_name=$(pw_dump | jq -r --argjson id "$target_sink_id" '.[] | select(.id == $id) | .info.props."node.nick" // .info.props."node.name" // "Unknown"' 2>/dev/null)

     # Dry-run mode: show what would happen
     if [[ "${DRY_RUN:-false}" == "true" ]]; then
         local current_sink_id current_sink_name
         current_sink_id=$(get_default_sink_id)
         current_sink_name=$(pw_dump | jq -r --argjson id "$current_sink_id" '.[] | select(.id == $id) | .info.props."node.nick" // .info.props."node.name" // "Unknown"' 2>/dev/null)
         dry_run_msg "Would switch sink"
         dry_run_msg "  Current sink: $current_sink_name (ID: $current_sink_id)"
         dry_run_msg "  Target sink: $target_sink_name (ID: $target_sink_id)"
         if not_empty "$target"; then
             dry_run_msg "  Target specified: $target"
         else
             dry_run_msg "  Action: cycle to next sink"
         fi
         return 0
     fi

     # Switch to the target sink
     local switch_output
     if ! switch_output=$(wpctl set-default "$target_sink_id" 2>&1); then
         error_with_suggestion "Failed to switch to sink ID $target_sink_id" \
             "The sink may not be available or accessible." \
             "Use 'volume list sinks' to verify the sink exists."
         if [[ "${VERBOSE:-false}" == "true" ]]; then
             echo "${COLOR_CYAN}[verbose]${COLOR_RESET} wpctl output: $switch_output" >&2
         fi
         return 1
     fi

     # Get display name and volume for notification
     target_sink_name=$(get_sink_display_name_by_id "$target_sink_id")
     local target_vol target_muted
     target_vol=$(wpctl get-volume "$target_sink_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
     target_muted=$(wpctl get-volume "$target_sink_id" 2>/dev/null | grep -q '\[MUTED\]' && echo true || echo false)

     # Invalidate cache and reinitialize audio
     invalidate_cache

     # Update NODE_ID and NODE_NAME to the new sink for potential future use
     NODE_ID="$target_sink_id"
     NODE_NAME=$(pw_dump | jq -r --argjson id "$target_sink_id" '.[] | select(.id == $id) | .info.props."node.name"' 2>/dev/null)

     # Show notification if enabled
     if $DISPLAY_NOTIFICATIONS; then
         local icon summary body=""

         # Get port information if available
         local port_info=""
         local port_desc
         port_desc=$(get_active_port_description 2>/dev/null || echo "")
         if not_empty "$port_desc"; then
             port_info=" - $port_desc"
         fi

         if $target_muted; then
             icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[0]}" || echo "${ICONS_SYMBOLIC[0]}")
             printf -v summary "Switched to: %s (MUTED)%s" "$target_sink_name" "$port_info"
         else
             icon=$(get_volume_icon "$target_vol")
             printf -v summary "Switched to: %s (%s%%)%s" "$target_sink_name" "$target_vol" "$port_info"
         fi

         case "$NOTIFICATION_METHOD" in
             libnotify|dunst|notify-osd)
                 notify_volume_libnotify "$target_vol" "$icon" "$summary" "$body"
                 ;;
             *)
                 if is_notification_plugin_available "$NOTIFICATION_METHOD"; then
                     call_notification_plugin "$NOTIFICATION_METHOD" "$target_vol" "$icon" "$summary" "$body" || notify_volume_libnotify "$target_vol" "$icon" "$summary" "$body"
                 else
                     notify_volume_libnotify "$target_vol" "$icon" "$summary" "$body"
                 fi
                 ;;
         esac
     else
         if $target_muted; then
             echo "Switched to: $target_sink_name (MUTED, ${target_vol}%)"
         else
             echo "Switched to: $target_sink_name (${target_vol}%)"
         fi
     fi

     # Update statusbar if configured
     update_statusbar || true
 }

next_sink() { switch_sink; }
prev_sink() {
     local -a all_sinks
     readarray -t all_sinks < <(get_all_sinks)

     if [[ ${#all_sinks[@]} -le 1 ]]; then
         error "Only one sink available. Nothing to switch to."
         return 1
     fi

     local current_sink_id
     current_sink_id=$(get_default_sink_id)

     if empty "$current_sink_id"; then
         error "Could not determine current default sink."
         return 1
     fi

     # Find current sink index
     local idx=0
     local found=false
     for sink in "${all_sinks[@]}"; do
         if [[ "$sink" == "$current_sink_id" ]]; then
             found=true
             break
         fi
         ((idx++))
     done

     if ! $found; then
         error "Current sink not found in available sinks."
         return 1
     fi

     # Move to previous sink (wrap around)
     idx=$(( (idx - 1 + ${#all_sinks[@]}) % ${#all_sinks[@]} ))
     local target_sink_id="${all_sinks[$idx]}"

     # Switch using the main function
     switch_sink "$target_sink_id"
 }

list_apps() {
     # List all applications with active audio streams
     local streams
     readarray -t streams < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Stream/Output/Audio") | "\(.id)|\(.info.props."application.name" // .info.props."media.name" // .info.props."application.process.binary" // "Unknown")|\(.info.props."node.name" // "N/A")"' 2>/dev/null)

     if [[ ${#streams[@]} -eq 0 ]]; then
         echo "${COLOR_YELLOW}No active audio streams found.${COLOR_RESET}"
         echo "Start an application that plays audio to see it here."
         return 0
     fi

     echo "${COLOR_YELLOW}Active Audio Applications:${COLOR_RESET}"
     echo

     local stream_id app_name stream_name vol muted
     for stream in "${streams[@]}"; do
         IFS='|' read -r stream_id app_name stream_name <<< "$stream"

         # Get volume and mute status
         vol=$(wpctl get-volume "$stream_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}' || echo "0")
         muted=$(wpctl get-volume "$stream_id" 2>/dev/null | grep -q '\[MUTED\]' && echo "MUTED" || echo "")

         printf "  ${COLOR_CYAN}%3s${COLOR_RESET}  ${COLOR_GREEN}%s${COLOR_RESET}" "$stream_id" "$app_name"
         if not_empty "$muted"; then
             printf "  ${COLOR_RED}[MUTED]${COLOR_RESET}  ${COLOR_YELLOW}%3s%%${COLOR_RESET}" "$vol"
         else
             printf "  ${COLOR_YELLOW}%3s%%${COLOR_RESET}" "$vol"
         fi
         if [[ "$stream_name" != "N/A" && "$stream_name" != "$app_name" ]]; then
             echo "  ${COLOR_MAGENTA}($stream_name)${COLOR_RESET}"
         else
             echo
         fi
     done
     echo
 }

find_app_stream() {
     # Find stream ID by application name (case-insensitive partial match)
     local -r search=$1
     local stream_id app_name

     # Try exact match first
     stream_id=$(pw_dump | jq -r --arg search "$search" '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Stream/Output/Audio" and (.info.props."application.name" == $search or .info.props."media.name" == $search or .info.props."application.process.binary" == $search)) | .id' 2>/dev/null | head -n1)

     if not_empty "$stream_id"; then
         echo "$stream_id"
         return 0
     fi

     # Try case-insensitive partial match
     # Get all streams and match in bash for better compatibility
     local streams
     readarray -t streams < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Stream/Output/Audio") | "\(.id)|\(.info.props."application.name" // .info.props."media.name" // .info.props."application.process.binary" // "")"' 2>/dev/null)

     local stream_id_match app_name search_lower app_lower
     search_lower=$(echo "$search" | tr '[:upper:]' '[:lower:]')
     for stream in "${streams[@]}"; do
         IFS='|' read -r stream_id_match app_name <<< "$stream"
         if not_empty "$app_name"; then
             app_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
             if [[ "$app_lower" == *"$search_lower"* ]]; then
                 echo "$stream_id_match"
                 return 0
             fi
         fi
     done

     return 1
 }

get_app_volume() {
     local -r stream_id=$1
     wpctl get-volume "$stream_id" 2>/dev/null | awk '{print $2 * 100}'
 }

is_app_muted() {
     local -r stream_id=$1
     wpctl get-volume "$stream_id" 2>/dev/null | grep -q '\[MUTED\]'
 }

set_app_volume() {
     local -r app_name=${1:?$(error 'Application name is required')}
     local -r vol=${2:?$(error 'Volume is required')}
     local -r op=${3:-}

     # Find the stream
     local stream_id
     stream_id=$(find_app_stream "$app_name")

     if empty "$stream_id"; then
         error_with_suggestion "Application not found: $app_name" \
             "Use 'volume app list' to see available applications." \
             "Application names are case-sensitive."
         return 1
     fi

     invalidate_cache

     local result
     case "$op" in
         +)
             if ! result=$(wpctl set-volume "$stream_id" "${vol}%+" 2>&1); then
                 error_with_suggestion "Failed to set volume for application: $app_name" \
                     "The application may have closed or the stream may be unavailable." \
                     "Use 'volume app list' to see currently available applications."
                 if [[ "${VERBOSE:-false}" == "true" ]] && not_empty "$result"; then
                     echo "${COLOR_CYAN}[verbose]${COLOR_RESET} wpctl output: $result" >&2
                 fi
                 return 1
             fi
             ;;
         -)
             if ! result=$(wpctl set-volume "$stream_id" "${vol}%-" 2>&1); then
                 error_with_suggestion "Failed to set volume for application: $app_name" \
                     "The application may have closed or the stream may be unavailable." \
                     "Use 'volume app list' to see currently available applications."
                 if [[ "${VERBOSE:-false}" == "true" ]] && not_empty "$result"; then
                     echo "${COLOR_CYAN}[verbose]${COLOR_RESET} wpctl output: $result" >&2
                 fi
                 return 1
             fi
             ;;
         *)
             if ! result=$(wpctl set-volume "$stream_id" "${vol}%" 2>&1); then
                 error_with_suggestion "Failed to set volume for application: $app_name" \
                     "The application may have closed or the stream may be unavailable." \
                     "Use 'volume app list' to see currently available applications."
                 if [[ "${VERBOSE:-false}" == "true" ]] && not_empty "$result"; then
                     echo "${COLOR_CYAN}[verbose]${COLOR_RESET} wpctl output: $result" >&2
                 fi
                 return 1
             fi
             # Small delay to ensure volume change takes effect
             sleep 0.05
             ;;
     esac
 }

increase_app_volume() {
     local -r app_name=${1:?$(error 'Application name is required')}
     local step=${2:-}
     if empty "$step"; then
         step=${DEFAULT_STEP:-5}
     fi
     set_app_volume "$app_name" "$step" "+"
 }

decrease_app_volume() {
     local -r app_name=${1:?$(error 'Application name is required')}
     local step=${2:-}
     if empty "$step"; then
         step=${DEFAULT_STEP:-5}
     fi
     set_app_volume "$app_name" "$step" "-"
 }

toggle_app_mute() {
     local -r app_name=${1:?$(error 'Application name is required')}

     # Find the stream
     local stream_id
     stream_id=$(find_app_stream "$app_name")

     if empty "$stream_id"; then
         error_with_suggestion "Application not found: $app_name" \
             "Use 'volume app list' to see available applications." \
             "Application names are case-sensitive."
         return 1
     fi

     invalidate_cache
     wpctl set-mute "$stream_id" toggle
 }

notify_app_volume() {
     local -r app_name=$1
     local -r stream_id=$2
     local -r vol=$(get_app_volume "$stream_id")
     local icon summary body=""

     if is_app_muted "$stream_id"; then
         printf -v summary "%s: muted" "$app_name"
         icon=$($USE_FULLCOLOR_ICONS && echo "${ICONS[0]}" || echo "${ICONS_SYMBOLIC[0]}")
     else
         printf -v summary "%s: %3s%%" "$app_name" "$vol"
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

show_app_notification() {
     local -r app_name=$1
     local stream_id

     $DISPLAY_NOTIFICATIONS || return

     # Find the stream
     stream_id=$(find_app_stream "$app_name")
     if empty "$stream_id"; then
         return 1
     fi

     if empty "$NOTIFICATION_METHOD"; then
         load_notify_server_info
         NOTIFICATION_METHOD=$NOTIFY_SERVER
     fi

     setup_notification_icons
     notify_app_volume "$app_name" "$stream_id"
 }

get_active_app_name() {
     # Get the name of the most recently active application (stream with highest volume or most recent)
     # This is a simple heuristic - could be improved
     local app_name
     app_name=$(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Stream/Output/Audio") | .info.props."application.name" // .info.props."media.name" // .info.props."application.process.binary" // empty' 2>/dev/null | head -n1)

     not_empty "$app_name" && echo "$app_name"
 }

get_balance() {
     # Get audio balance (left/right channel balance) from PipeWire
     # Returns balance as a value from -100 (left) to +100 (right), or 0 (centered)
     if empty "$NODE_ID"; then
         echo "0"
         return 0
     fi

     # First check if we have a stored balance preference for this sink
     # Check by ID first
     if isset "SINK_BALANCE[$NODE_ID]"; then
         echo "${SINK_BALANCE[$NODE_ID]}"
         return 0
     fi

     # Check by name
     if isset "SINK_BALANCE[$NODE_NAME]"; then
         echo "${SINK_BALANCE[$NODE_NAME]}"
         return 0
     fi

     # Check by nick
     if not_empty "$NODE_NICK" && isset "SINK_BALANCE[$NODE_NICK]"; then
         echo "${SINK_BALANCE[$NODE_NICK]}"
         return 0
     fi

     # Try to get channel volumes from pw-dump
     # Channel volumes are stored in .info.params.Props[].channelVolumes
     local left_vol right_vol
     left_vol=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.Props[]? | .channelVolumes[0]? // empty' 2>/dev/null)
     right_vol=$(pw_dump | jq -r --argjson node_id "$NODE_ID" '.[] | select(.id == $node_id) | .info.params.Props[]? | .channelVolumes[1]? // empty' 2>/dev/null)

     # If we can't get channel volumes from pw-dump, default to centered
     if empty "$left_vol" || empty "$right_vol"; then
         echo "0"
         return 0
     fi

     # Calculate balance: positive = right, negative = left
     # Convert volumes to numeric values and calculate difference
     local left_num right_num balance
     left_num=$(printf "%.2f" "$left_vol" 2>/dev/null || echo "0")
     right_num=$(printf "%.2f" "$right_vol" 2>/dev/null || echo "0")

     # If volumes are equal, balance is 0
     if [[ "$left_num" == "$right_num" ]]; then
         echo "0"
         return 0
     fi

     # Calculate balance using awk for floating point arithmetic
     balance=$(awk -v left="$left_num" -v right="$right_num" 'BEGIN {
         diff = right - left
         # Normalize to -100..100 range (assuming volumes are 0.0-1.0)
         balance = diff * 100
         if (balance > 100) balance = 100
         if (balance < -100) balance = -100
         printf "%.0f", balance
     }' 2>/dev/null || echo "0")

    echo "$balance"
}

# Get effective balance for current sink (per-sink or global)
get_effective_balance() {
    if empty "$NODE_ID" || empty "$NODE_NAME"; then
        echo "0"
        return 0
    fi

    # Check by ID first
    if isset "SINK_BALANCE[$NODE_ID]"; then
        echo "${SINK_BALANCE[$NODE_ID]}"
        return 0
    fi

    # Check by name
    if isset "SINK_BALANCE[$NODE_NAME]"; then
        echo "${SINK_BALANCE[$NODE_NAME]}"
        return 0
    fi

    # Check by nick
    if not_empty "$NODE_NICK" && isset "SINK_BALANCE[$NODE_NICK]"; then
        echo "${SINK_BALANCE[$NODE_NICK]}"
        return 0
    fi

    # Fall back to current balance from PipeWire
    # Note: pw-dump may not return channelVolumes values, so we default to 0
    # if no stored preference exists
    get_balance
}

set_balance() {
    local -r balance_val=${1:?$(error 'Balance value is required')}
    local -r op=${2:-}

    if empty "$NODE_ID"; then
        error "No audio sink available"
        return 1
    fi

    # Validate balance range: -100 to +100
    local target_balance current_balance
    current_balance=$(get_balance)

    case "$op" in
        +)
            # Relative increase
            target_balance=$(( current_balance + balance_val ))
            ;;
        -)
            # Relative decrease
            target_balance=$(( current_balance - balance_val ))
            ;;
        *)
            # Absolute value
            target_balance=$balance_val
            ;;
    esac

    # Clamp to valid range
    if (( target_balance > 100 )); then
        target_balance=100
    elif (( target_balance < -100 )); then
        target_balance=-100
    fi

    # Get current volume to maintain overall volume level
    local current_vol
    current_vol=$(get_volume)
    if empty "$current_vol"; then
        current_vol=100
    fi

    # Calculate left and right channel volumes
    # Balance: -100 (all left) to +100 (all right)
    # When balance is 0, both channels are equal
    # When balance is positive (right), right channel is louder
    # When balance is negative (left), left channel is louder
    local left_vol right_vol
    if (( target_balance == 0 )); then
        # Centered: both channels at current volume
        left_vol=$current_vol
        right_vol=$current_vol
    elif (( target_balance > 0 )); then
        # Shift right: reduce left, increase right
        # Balance is 0-100, convert to factor 0.0-1.0
        local balance_factor
        balance_factor=$(awk "BEGIN {printf \"%.3f\", $target_balance / 100}" 2>/dev/null || echo "0")
        # Left channel: reduce by balance factor
        left_vol=$(awk "BEGIN {printf \"%.0f\", $current_vol * (1.0 - $balance_factor)}" 2>/dev/null || echo "$current_vol")
        # Right channel: increase by balance factor (but don't exceed max)
        right_vol=$(awk "BEGIN {printf \"%.0f\", $current_vol * (1.0 + $balance_factor)}" 2>/dev/null || echo "$current_vol")
        # Clamp right channel to max volume
        local effective_max_vol
        effective_max_vol=$(get_effective_max_vol)
        if not_empty "$effective_max_vol" && (( right_vol > effective_max_vol )); then
            right_vol=$effective_max_vol
        fi
    else
        # Shift left: increase left, reduce right
        # Balance is -100 to 0, convert to factor 0.0-1.0
        local balance_factor
        balance_factor=$(awk "BEGIN {printf \"%.3f\", -$target_balance / 100}" 2>/dev/null || echo "0")
        # Left channel: increase by balance factor (but don't exceed max)
        left_vol=$(awk "BEGIN {printf \"%.0f\", $current_vol * (1.0 + $balance_factor)}" 2>/dev/null || echo "$current_vol")
        # Clamp left channel to max volume
        local effective_max_vol
        effective_max_vol=$(get_effective_max_vol)
        if not_empty "$effective_max_vol" && (( left_vol > effective_max_vol )); then
            left_vol=$effective_max_vol
        fi
        # Right channel: reduce by balance factor
        right_vol=$(awk "BEGIN {printf \"%.0f\", $current_vol * (1.0 - $balance_factor)}" 2>/dev/null || echo "$current_vol")
    fi

    # Ensure volumes are non-negative
    if (( left_vol < 0 )); then
        left_vol=0
    fi
    if (( right_vol < 0 )); then
        right_vol=0
    fi

    # Set channel volumes using pw-cli
    # Convert percentages to 0.0-1.0 range for PipeWire
    local left_pw right_pw
    left_pw=$(awk "BEGIN {printf \"%.3f\", $left_vol / 100}" 2>/dev/null || echo "0")
    right_pw=$(awk "BEGIN {printf \"%.3f\", $right_vol / 100}" 2>/dev/null || echo "0")

    # Use pw-cli to set channel volumes
    # Format: pw-cli s <node_id> Props '{ channelVolumes: [left, right] }'
    local result pw_cmd
    # Construct command with proper JSON format (no quotes around channelVolumes key)
    # Using eval to properly handle the single quotes in the JSON
    pw_cmd="pw-cli s $NODE_ID Props '{ channelVolumes: [$left_pw, $right_pw] }'"
    if ! result=$(eval "$pw_cmd" 2>&1); then
        error "Failed to set balance. pw-cli may not be available or the sink may not support channel volume control."
        if [[ "${VERBOSE:-false}" == "true" ]] && not_empty "$result"; then
            echo "${COLOR_CYAN}[verbose]${COLOR_RESET} pw-cli output: $result" >&2
        fi
        return 1
    fi

    # Store balance preference per sink (before invalidating cache)
    if not_empty "$NODE_ID"; then
        SINK_BALANCE["$NODE_ID"]=$target_balance
    fi
    if not_empty "$NODE_NAME"; then
        SINK_BALANCE["$NODE_NAME"]=$target_balance
    fi
    if not_empty "$NODE_NICK"; then
        SINK_BALANCE["$NODE_NICK"]=$target_balance
    fi

    # Invalidate cache so next get_balance() call will use stored preference
    invalidate_cache
}

get_volume_color_code() {
     # Get ANSI color code for volume level
     # Returns terminal color escape sequence
     local -ir vol=${1:-$(get_volume)}
     if has_color; then
         if is_muted 2>/dev/null; then
             echo "$COLOR_RED"
         else
             volume_color "$vol"
         fi
     else
         echo ""
     fi
 }

analyze_volumes() {
     # Analyze volumes across all sinks and apps
     # Returns: target_vol, adjustments array
     local -r target=${1:-}  # Optional target volume
     local -a all_sinks
     local -a adjustments
     local total_vol=0
     local count=0
     local sink_id vol display_name
     # shellcheck disable=SC2034  # Used externally by normalize_volume
     declare -g NORMALIZE_TARGET_VOL
     # shellcheck disable=SC2034  # Used externally by normalize_volume
     declare -ga NORMALIZE_ADJUSTMENTS
     # shellcheck disable=SC2034  # Used externally by normalize_volume
     declare -gi NORMALIZE_COUNT

     readarray -t all_sinks < <(get_all_sinks)

     # Collect sink volumes
     for sink_id in "${all_sinks[@]}"; do
         vol=$(wpctl get-volume "$sink_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}' || echo "0")
         if not_empty "$vol"; then
             total_vol=$((total_vol + vol))
             ((count++))
             display_name=$(get_sink_display_name_by_id "$sink_id")
             adjustments+=("$sink_id|$display_name|$vol|sink")
         fi
     done

     # Collect app stream volumes
     local streams
     readarray -t streams < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Stream/Output/Audio") | "\(.id)|\(.info.props."application.name" // .info.props."media.name" // .info.props."application.process.binary" // "Unknown")"' 2>/dev/null)

     local stream_id app_name
     for stream in "${streams[@]}"; do
         IFS='|' read -r stream_id app_name <<< "$stream"
         vol=$(wpctl get-volume "$stream_id" 2>/dev/null | awk '{printf "%.0f", $2 * 100}' || echo "0")
         if not_empty "$vol"; then
             total_vol=$((total_vol + vol))
             ((count++))
             adjustments+=("$stream_id|$app_name|$vol|app")
         fi
     done

     # Calculate target volume
     local target_vol
     if not_empty "$target"; then
         target_vol=$target
     elif (( count > 0 )); then
         # Calculate average
         target_vol=$((total_vol / count))
     else
         target_vol=100  # Default if nothing found
     fi

     # Clamp target to valid range
     local effective_max_vol
     effective_max_vol=$(get_effective_max_vol)
     if not_empty "$effective_max_vol" && (( target_vol > effective_max_vol )); then
         target_vol=$effective_max_vol
     fi
     if (( target_vol < 0 )); then
         target_vol=0
     fi

     # Return results via global variables (bash limitation)
     NORMALIZE_TARGET_VOL=$target_vol
     NORMALIZE_ADJUSTMENTS=("${adjustments[@]}")
     NORMALIZE_COUNT=$count
 }

normalize_volume() {
     local -r mode=${1:-}  # "suggest", "apply", or "auto"
     local -r target=${2:-}  # Optional target volume
     local -r interval=${3:-5}  # For auto mode: check interval in seconds

     if [[ "$mode" == "auto" ]]; then
         # Auto-normalization mode: continuously monitor and adjust
         echo "${COLOR_YELLOW}Auto-normalization mode started. Press Ctrl+C to stop.${COLOR_RESET}"
         echo "Checking every ${interval} seconds..."
         echo

         while true; do
             analyze_volumes "$target"
             local adjustments=("${NORMALIZE_ADJUSTMENTS[@]}")
             local target_vol=$NORMALIZE_TARGET_VOL
             local adjusted=0

             for adjustment in "${adjustments[@]}"; do
                 IFS='|' read -r id name current_vol type <<< "$adjustment"
                 local diff=$((target_vol - current_vol))
                 local abs_diff
                 if (( diff < 0 )); then
                     abs_diff=$((-diff))
                 else
                     abs_diff=$diff
                 fi

                 # Only adjust if difference is significant (>= 5%)
                 if (( abs_diff >= 5 )); then
                     if [[ "$type" == "sink" ]]; then
                         wpctl set-volume "$id" "${target_vol}%" &>/dev/null
                     else
                         wpctl set-volume "$id" "${target_vol}%" &>/dev/null
                     fi
                     ((adjusted++))
                 fi
             done

             if (( adjusted > 0 )); then
                 invalidate_cache
                 echo "[$(date +%H:%M:%S)] Normalized $adjusted source(s) to ${target_vol}%"
             fi

             sleep "$interval"
         done
     else
         # Analyze current volumes
         analyze_volumes "$target"
         local adjustments=("${NORMALIZE_ADJUSTMENTS[@]}")
         local target_vol=$NORMALIZE_TARGET_VOL
         local count=$NORMALIZE_COUNT

         if (( count == 0 )); then
             error "No audio sources found to normalize."
             return 1
         fi

         echo "${COLOR_YELLOW}Volume Normalization Analysis${COLOR_RESET}"
         echo "Target volume: ${COLOR_GREEN}${target_vol}%${COLOR_RESET}"
         echo "Found ${count} source(s)"
         echo

         local needs_adjustment=false
         local adjustment_count=0

         for adjustment in "${adjustments[@]}"; do
             IFS='|' read -r id name current_vol type <<< "$adjustment"
             local diff=$((target_vol - current_vol))
             local abs_diff
             if (( diff < 0 )); then
                 abs_diff=$((-diff))
             else
                 abs_diff=$diff
             fi

             if (( abs_diff >= 1 )); then  # Show if difference >= 1%
                 needs_adjustment=true
                 local type_label
                 if [[ "$type" == "sink" ]]; then
                     type_label="Sink"
                 else
                     type_label="App"
                 fi

                 if (( diff > 0 )); then
                     printf "  ${COLOR_CYAN}%s${COLOR_RESET} (${type_label}): ${COLOR_YELLOW}%3s%%${COLOR_RESET} → ${COLOR_GREEN}%3s%%${COLOR_RESET} (+%2s%%)" "$name" "$current_vol" "$target_vol" "$diff"
                 else
                     printf "  ${COLOR_CYAN}%s${COLOR_RESET} (${type_label}): ${COLOR_YELLOW}%3s%%${COLOR_RESET} → ${COLOR_GREEN}%3s%%${COLOR_RESET} (%2s%%)" "$name" "$current_vol" "$target_vol" "$diff"
                 fi

                 if [[ "$mode" == "apply" ]]; then
                     if [[ "$type" == "sink" ]]; then
                         wpctl set-volume "$id" "${target_vol}%" &>/dev/null
                     else
                         wpctl set-volume "$id" "${target_vol}%" &>/dev/null
                     fi
                     echo " ${COLOR_GREEN}[APPLIED]${COLOR_RESET}"
                     ((adjustment_count++))
                 else
                     echo
                 fi
             else
                 # Show sources that are already at target
                 local type_label
                 if [[ "$type" == "sink" ]]; then
                     type_label="Sink"
                 else
                     type_label="App"
                 fi
                 printf "  ${COLOR_CYAN}%s${COLOR_RESET} (${type_label}): ${COLOR_GREEN}%3s%%${COLOR_RESET} (already normalized)" "$name" "$current_vol"
                 echo
             fi
         done

         echo

         if [[ "$mode" == "apply" ]]; then
             if (( adjustment_count > 0 )); then
                 invalidate_cache
                 echo "${COLOR_GREEN}Normalized ${adjustment_count} source(s) to ${target_vol}%${COLOR_RESET}"
             else
                 echo "All sources already normalized."
             fi
         elif $needs_adjustment; then
             echo "Use ${COLOR_GREEN}normalize apply${COLOR_RESET} to apply these adjustments."
             echo "Or use ${COLOR_GREEN}normalize apply <target>${COLOR_RESET} to set a specific target volume."
         else
             echo "All sources are already normalized."
         fi
     fi
 }

normalize() {
     local -r subcommand=${1:-suggest}
     local -r target=${2:-}

     case "$subcommand" in
         suggest|analyze)
             normalize_volume "suggest" "$target"
             ;;
         apply)
             normalize_volume "apply" "$target"
             ;;
         auto)
             local -r interval=${3:-5}
             normalize_volume "auto" "$target" "$interval"
             ;;
         "")
             error "Normalize subcommand required. Use: normalize suggest|apply|auto"
             echo "  ${COLOR_GREEN}normalize suggest${COLOR_RESET}     - analyze and suggest volume adjustments"
             echo "  ${COLOR_GREEN}normalize apply${COLOR_RESET}       - analyze and apply volume adjustments"
             echo "  ${COLOR_GREEN}normalize apply <target>${COLOR_RESET} - normalize to specific target volume"
             echo "  ${COLOR_GREEN}normalize auto [interval]${COLOR_RESET} - auto-normalization mode (default: 5s)"
             EXITCODE=$EX_USAGE
             return 1
             ;;
         *)
             # If subcommand is a number, treat it as target volume for apply
             if [[ "$subcommand" =~ ^[0-9]+$ ]]; then
                 normalize_volume "apply" "$subcommand"
             else
                 error "Unknown normalize subcommand: $subcommand"
                 echo "Valid subcommands: suggest, apply, auto"
                 EXITCODE=$EX_USAGE
                 return 1
             fi
             ;;
     esac
 }

app() {
     local -r subcommand=${1:-}
     local -r app_name=${2:-}
     local -r value=${3:-}

     case "$subcommand" in
         list)
             list_apps
             ;;
         "")
             error "App subcommand required. Use: app list|app <name> <cmd>"
             echo "  ${COLOR_GREEN}app list${COLOR_RESET}              - list all applications with audio streams"
             echo "  ${COLOR_GREEN}app <name> up [value]${COLOR_RESET}   - increase application volume"
             echo "  ${COLOR_GREEN}app <name> down [value]${COLOR_RESET} - decrease application volume"
             echo "  ${COLOR_GREEN}app <name> set <value>${COLOR_RESET} - set application volume"
             echo "  ${COLOR_GREEN}app <name> mute${COLOR_RESET}        - toggle application mute"
             EXITCODE=$EX_USAGE
             return 1
             ;;
         *)
             # subcommand is app name, app_name is the volume command
             if empty "$app_name"; then
                 error "Command required. Use: app <name> <cmd>"
                 echo "Valid commands: up, down, set, mute"
                 echo "Use 'volume app list' to see available applications."
                 EXITCODE=$EX_USAGE
                 return 1
             fi

             case "$app_name" in
                 up|raise|increase)
                     if empty "$value"; then
                         increase_app_volume "$subcommand"
                     else
                         increase_app_volume "$subcommand" "$value"
                     fi
                     show_app_notification "$subcommand"
                     ;;
                 down|lower|decrease)
                     if empty "$value"; then
                         decrease_app_volume "$subcommand"
                     else
                         decrease_app_volume "$subcommand" "$value"
                     fi
                     show_app_notification "$subcommand"
                     ;;
                 set)
                     if empty "$value"; then
                         error "Volume value required. Use: app <name> set <value>"
                         EXITCODE=$EX_USAGE
                         return 1
                     fi
                     case "$value" in
                         +*) increase_app_volume "$subcommand" "${value:1}" ;;
                         -*) decrease_app_volume "$subcommand" "${value:1}" ;;
                         *) set_app_volume "$subcommand" "$value" ;;
                     esac
                     show_app_notification "$subcommand"
                     ;;
                 mute)
                     toggle_app_mute "$subcommand"
                     show_app_notification "$subcommand"
                     ;;
                 *)
                     error "Unknown app command: $app_name"
                     echo "Valid commands: up, down, set, mute"
                     EXITCODE=$EX_USAGE
                     return 1
                     ;;
             esac
             ;;
     esac
 }

usage() {
     cat <<- EOF 1>&2
${COLOR_YELLOW}Usage:${COLOR_RESET} $0 [<options>] <command> [<args>]
Control volume and related notifications.

${COLOR_YELLOW}Commands:${COLOR_RESET}
  ${COLOR_GREEN}up [value]${COLOR_RESET}                  increase volume (uses default step if value omitted)
  ${COLOR_GREEN}down [value]${COLOR_RESET}                decrease volume (uses default step if value omitted)
  ${COLOR_GREEN}set <value>${COLOR_RESET}                 set volume
  ${COLOR_GREEN}wheel <delta>${COLOR_RESET}               mouse wheel volume control (accumulates small changes)
                           examples:
                               wheel 2.0  - scroll up (positive delta)
                               wheel -2.0 - scroll down (negative delta)
                           note: accumulates changes until reaching DEFAULT_STEP threshold
  ${COLOR_GREEN}mute${COLOR_RESET}                        toggle mute
  ${COLOR_GREEN}fade <from> <to> [duration_ms]${COLOR_RESET} fade volume smoothly
                           examples:
                               fade 0 100       - fade from 0% to 100% (500ms)
                               fade 0 100 2000  - fade from 0% to 100% over 2 seconds
  ${COLOR_GREEN}mic <cmd> [value]${COLOR_RESET}           control microphone
                           commands:
                               up <value>    - increase microphone volume
                               down <value>  - decrease microphone volume
                               set <value>   - set microphone volume
                               mute          - toggle microphone mute
  ${COLOR_GREEN}listen [options] [output_format]${COLOR_RESET} monitor volume changes
                           options:
                               -a, --all          - monitor all sinks
                               -I, --input        - monitor input sources
                               --watch            - show real-time updates in terminal
                               --volume-only      - only show volume change events
                               --mute-only        - only show mute change events
                           examples:
                               listen                    - monitor default sink
                               listen -a                 - monitor all sinks
                               listen -I                 - monitor all input sources
                               listen --watch            - show terminal output
                               listen -a --watch         - monitor all sinks with terminal output
                               listen --volume-only      - only volume changes
                               listen i3blocks           - output in i3blocks format
  ${COLOR_GREEN}list <type>${COLOR_RESET}                 list sinks, sources, or ports
                           types:
                               sinks   - list all audio output sinks
                               sources - list all audio input sources
                               ports   - list ports for current sink (BETA: shows availability status)
  ${COLOR_GREEN}switch [sink]${COLOR_RESET}               switch to next sink or specified sink
  ${COLOR_GREEN}next${COLOR_RESET}                        switch to next sink
  ${COLOR_GREEN}prev${COLOR_RESET}                        switch to previous sink
  ${COLOR_GREEN}port <cmd> [port]${COLOR_RESET}           control audio ports (BETA/EXPERIMENTAL)
                           commands:
                               list        - list available ports with availability status
                               set <port>  - set active port
                           note: Port features are experimental and may not work on all devices
  ${COLOR_GREEN}profile <cmd> [name]${COLOR_RESET}       manage volume profiles
                           commands:
                               save <name>   - save current settings as profile
                               load <name>   - load a saved profile
                               list          - list all saved profiles
                               delete <name> - delete a profile
                           quick access:
                               profile <name> - load profile (shortcut for load)
  ${COLOR_GREEN}boost <amount> [timeout]${COLOR_RESET}   temporarily boost volume
                           examples:
                               boost 20       - boost by 20% for 30s (default)
                               boost 20 60    - boost by 20% for 60s
                               boost off      - cancel active boost
  ${COLOR_GREEN}sync${COLOR_RESET}                        sync volume across all active sinks
  ${COLOR_GREEN}balance [value]${COLOR_RESET}             control stereo balance (left/right)
                           examples:
                               balance          - show current balance
                               balance 0        - center balance
                               balance -10      - shift 10% left
                               balance +10      - shift 10% right
                               balance -100     - full left
                               balance 100      - full right
                           note: Balance range is -100 (left) to +100 (right), 0 is centered
                           Balance preference is stored per sink
  ${COLOR_GREEN}normalize [cmd] [target]${COLOR_RESET}    normalize volume across sources
                           commands:
                               suggest         - analyze and suggest adjustments (default)
                               apply           - analyze and apply adjustments
                               apply <target>  - normalize to specific target volume
                               auto [interval] - auto-normalization mode (default: 5s)
                           examples:
                               normalize                    - suggest volume adjustments
                               normalize apply              - normalize all sources to average
                               normalize apply 75           - normalize all sources to 75%
                               normalize auto               - auto-normalize every 5 seconds
                               normalize auto 10            - auto-normalize every 10 seconds
                           note: Analyzes volumes across all sinks and applications
                           Useful for consistent volume levels across different audio sources
  ${COLOR_GREEN}app <cmd> [args]${COLOR_RESET}            control per-application volume
                           commands:
                               list                    - list all applications with audio streams
                               <name> up [value]       - increase application volume
                               <name> down [value]     - decrease application volume
                               <name> set <value>      - set application volume
                               <name> mute             - toggle application mute
                           examples:
                               app list                - show all active applications
                               app firefox up 5        - increase Firefox volume by 5%
                               app mpv mute            - mute/unmute mpv
  ${COLOR_GREEN}output <format>${COLOR_RESET}             display volume in a custom format
                           special formats:
                               json                        - JSON output with all volume information
                           format placeholders:
                               %v = volume
                               %s = sink name
                               %p = volume progress bar
                               %i = volume icon/emoji
                               %P = active port description (BETA: includes availability status when available)
                               %m = microphone volume
                               %a = active application name
                               %b = balance (L=left, R=right, C=center)
                               %c = color codes (ANSI terminal colors)
                               %n = node display name/alias
                               %d = node id

                           conditional formatting:
                               %v{>50:high:low}  - if volume > 50, show "high", else "low"
                               %v{<30:quiet:normal} - if volume < 30, show "quiet", else "normal"
                               %m{>80:loud:normal} - conditional on microphone volume
                               %b{!=0:unbalanced:centered} - conditional on balance

                               examples:
                                   output json              - JSON format for programmatic use
                                   "Volume is %v" = Volume is 50%
                                   "%i %v %p \n"  = 奔 50% ██████████
                                   "%c%v${COLOR_RESET}" = colored volume (if terminal supports)
                                   "%v{>50:high:low}" = "high" if volume > 50%, else "low"
  ${COLOR_GREEN}outputs${COLOR_RESET}                     show supported output formats
  ${COLOR_GREEN}notifications${COLOR_RESET}               list notification methods
  ${COLOR_GREEN}config <cmd>${COLOR_RESET}                manage configuration
                           commands:
                               show        - show current configuration
                               validate    - validate config file syntax
                               docs        - show all configurable variables
  ${COLOR_GREEN}undo${COLOR_RESET}                        restore previous volume level
                           examples:
                               undo        - revert to last volume before current change
                           note: History is tracked automatically for volume changes
  ${COLOR_GREEN}history [count]${COLOR_RESET}             show volume change history
                           examples:
                               history     - show last 10 volume changes
                               history 20  - show last 20 volume changes
                           note: History persists across sessions in config directory
  ${COLOR_GREEN}help${COLOR_RESET}                        show help

${COLOR_YELLOW}Options:${COLOR_RESET}
  ${COLOR_GREEN}-n${COLOR_RESET}                          enable notifications
  ${COLOR_GREEN}-q${COLOR_RESET}, ${COLOR_GREEN}--no-notify${COLOR_RESET}          disable notifications (quiet mode)
  ${COLOR_GREEN}-C${COLOR_RESET}                          play event sounds using libcanberra
  ${COLOR_GREEN}-P${COLOR_RESET}                          play sound for volume changes
  ${COLOR_GREEN}-j <muted,high,low,medium>${COLOR_RESET}  custom volume emojis
  ${COLOR_GREEN}-s <sink>${COLOR_RESET}                   specify sink (${COLOR_MAGENTA}default: @DEFAULT_AUDIO_SINK@${COLOR_RESET})
  ${COLOR_GREEN}-I <source>${COLOR_RESET}                 specify input source (${COLOR_MAGENTA}default: @DEFAULT_AUDIO_SOURCE@${COLOR_RESET})
  ${COLOR_GREEN}-a${COLOR_RESET}                          operate on all sinks (${COLOR_MAGENTA}for up/down/set/mute${COLOR_RESET})
  ${COLOR_GREEN}-t <process_name>${COLOR_RESET}           status bar process name (${COLOR_MAGENTA}requires -u${COLOR_RESET})
  ${COLOR_GREEN}-A <node.nick:alias>${COLOR_RESET}        alias a node nick (e.g., -A "ALC287 Analog:Speakers")
  ${COLOR_GREEN}-u <signal>${COLOR_RESET}                 signal to update status bar (${COLOR_MAGENTA}requires -t${COLOR_RESET})
  ${COLOR_GREEN}-D <value>${COLOR_RESET}                  set default step size (${COLOR_MAGENTA}default: 5${COLOR_RESET})
  ${COLOR_GREEN}-f <duration_ms>${COLOR_RESET}            fade duration in milliseconds (${COLOR_MAGENTA}for set/up/down/mute${COLOR_RESET})
  ${COLOR_GREEN}-x <value>${COLOR_RESET}                  set maximum volume
  ${COLOR_GREEN}-U <unit>${COLOR_RESET}                   display unit for volume output (${COLOR_MAGENTA}percent${COLOR_RESET} or ${COLOR_MAGENTA}db${COLOR_RESET})
  ${COLOR_GREEN}-v${COLOR_RESET}                          verbose mode (detailed error information)
  ${COLOR_GREEN}-d${COLOR_RESET}, ${COLOR_GREEN}--dry-run${COLOR_RESET}          show what would happen without executing (test mode)
  ${COLOR_GREEN}--log [file|syslog]${COLOR_RESET}         enable logging to file or syslog (${COLOR_MAGENTA}default: syslog${COLOR_RESET} if no file specified)
  ${COLOR_GREEN}--debug${COLOR_RESET}                     enable debug mode with verbose logging (${COLOR_MAGENTA}requires --log${COLOR_RESET})
  ${COLOR_GREEN}--exit-code${COLOR_RESET}                 show detailed exit code information
  ${COLOR_GREEN}-h${COLOR_RESET}                          show help

${COLOR_YELLOW}Notification Options:${COLOR_RESET}
  ${COLOR_GREEN}-N <method>${COLOR_RESET}                 notification method (${COLOR_MAGENTA}default: libnotify${COLOR_RESET})
  ${COLOR_GREEN}-p${COLOR_RESET}                          enable progress bar in notifications
  ${COLOR_GREEN}-L <placement>${COLOR_RESET}              progress bar placement (${COLOR_MAGENTA}default: summary${COLOR_RESET}; ${COLOR_MAGENTA}requires -p${COLOR_RESET})
                           placements:
                               body
                               summary
  ${COLOR_GREEN}-e <ms>${COLOR_RESET}                     notification expiration time
  ${COLOR_GREEN}-l${COLOR_RESET}                          use full-color icons
  ${COLOR_GREEN}-S <suffix>${COLOR_RESET}                 add suffix to symbolic icon names
  ${COLOR_GREEN}-y${COLOR_RESET}                          use dunstify (${COLOR_MAGENTA}default: notify-send${COLOR_RESET})

${COLOR_YELLOW}Notification Features:${COLOR_RESET}
  Notifications show sink name when multiple sinks are available
  Port information is displayed in notifications when available (BETA/EXPERIMENTAL)
  Port change detection shows when active port changes (BETA/EXPERIMENTAL)
  Auto-suggestions for newly available ports (BETA/EXPERIMENTAL)
  Sink and port changes trigger enhanced notifications
  Set ${COLOR_CYAN}NOTIFICATION_GROUP=true${COLOR_RESET} in config to group volume change notifications

${COLOR_YELLOW}Environment Variables:${COLOR_RESET}
  ${COLOR_CYAN}XOSD_PATH${COLOR_RESET}                   path to osd_cat
  ${COLOR_CYAN}HERBE_PATH${COLOR_RESET}                  path to herbe
  ${COLOR_CYAN}VOLNOTI_PATH${COLOR_RESET}                path to volnoti-show
  ${COLOR_CYAN}CANBERRA_PATH${COLOR_RESET}               path to canberra-gtk-play
  ${COLOR_CYAN}NOTIFY_PATH${COLOR_RESET}                 path to command that sends notifications
  ${COLOR_CYAN}NO_NOTIFY_COLOR${COLOR_RESET}             flag to disable colors in notifications
  ${COLOR_CYAN}USE_NOTIFY_SEND_PY${COLOR_RESET}          flag to use notify-send.py instead of notify-send
  ${COLOR_CYAN}NOTIFICATION_GROUP${COLOR_RESET}          set to "true" to group volume change notifications (dunst only)

${COLOR_YELLOW}Exit Codes:${COLOR_RESET}
  ${COLOR_GREEN}0${COLOR_RESET}   Success - command executed successfully
  ${COLOR_GREEN}33${COLOR_RESET}  Urgent - volume exceeds maximum limit (MAX_VOL)
  ${COLOR_GREEN}64${COLOR_RESET}  Usage error - invalid command, option, or argument
  ${COLOR_GREEN}69${COLOR_RESET}  Unavailable - required tool or feature not available

  Use ${COLOR_GREEN}--exit-code${COLOR_RESET} to display detailed exit code information.
EOF
     exit "$EX_USAGE"
 }

show_exit_codes() {
     cat <<- EOF
${COLOR_YELLOW}Exit Codes:${COLOR_RESET}

${COLOR_GREEN}0${COLOR_RESET}   ${COLOR_CYAN}EX_OK${COLOR_RESET}
     Success - command executed successfully
     All operations completed without errors

${COLOR_GREEN}33${COLOR_RESET}  ${COLOR_CYAN}EX_URGENT${COLOR_RESET}
     Urgent - volume exceeds maximum limit
     Returned when volume is set above MAX_VOL threshold
     Indicates potential audio distortion or hardware limits

${COLOR_GREEN}64${COLOR_RESET}  ${COLOR_CYAN}EX_USAGE${COLOR_RESET}
     Usage error - invalid command, option, or argument
     Common causes:
       - Invalid command name
       - Missing required arguments
       - Invalid option values
       - Incorrect command syntax
     Check command usage with: ${COLOR_GREEN}$0 help${COLOR_RESET}

${COLOR_GREEN}69${COLOR_RESET}  ${COLOR_CYAN}EX_UNAVAILABLE${COLOR_RESET}
     Unavailable - required tool or feature not available
     Common causes:
       - Required notification tool not found (notify-send, dunstify, etc.)
       - Audio system not available (PipeWire/PulseAudio)
       - Required external command missing
     Check verbose mode with: ${COLOR_GREEN}$0 -v <command>${COLOR_RESET}

${COLOR_YELLOW}Usage in Scripts:${COLOR_RESET}
  Check exit codes in your scripts:
 if ! $0 up 5; then
     case \$? in
         64) echo "Usage error" ;;
         69) echo "Tool unavailable" ;;
         33) echo "Volume limit exceeded" ;;
     esac
 fi

EOF
 }

# Volume history tracking functions
get_volume_history_file() {
    local config_dir
    config_dir=$(get_config_dir)
    echo "$config_dir/.volume_history"
}

get_volume_history_max_size() {
    # Default to 20 entries, can be overridden via VOLUME_HISTORY_SIZE config
    echo "${VOLUME_HISTORY_SIZE:-20}"
}

save_volume_to_history() {
    local -r vol=$1
    local history_file current_vol
    history_file=$(get_volume_history_file)
    local config_dir
    config_dir=$(get_config_dir)

    # Get current volume if not provided (shouldn't happen, but safety check)
    if empty "$vol"; then
        current_vol=$(get_volume 2>/dev/null || echo "0")
    else
        current_vol=$vol
    fi

    # Skip if volume is the same as the last entry (avoid duplicates)
    if [[ -f "$history_file" ]]; then
        local last_vol
        last_vol=$(tail -n 1 "$history_file" 2>/dev/null | cut -d'|' -f1)
        if [[ "$last_vol" == "$current_vol" ]]; then
            return 0
        fi
    fi

    # Create config directory if it doesn't exist
    mkdir -p "$config_dir" || {
        return 1
    }

    # Format: volume|node_id|timestamp
    local timestamp
    timestamp=$(date +%s 2>/dev/null || echo "0")
    local entry="${current_vol}|${NODE_ID:-default}|${timestamp}"

    # Append to history file
    echo "$entry" >> "$history_file" 2>/dev/null || {
        return 1
    }

    # Trim history to max size
    trim_volume_history
}

trim_volume_history() {
    local history_file max_size
    history_file=$(get_volume_history_file)
    max_size=$(get_volume_history_max_size)

    if [[ ! -f "$history_file" ]]; then
        return 0
    fi

    local line_count
    line_count=$(wc -l < "$history_file" 2>/dev/null || echo "0")

    if (( line_count > max_size )); then
        # Keep only the last max_size entries
        local temp_file
        temp_file=$(mktemp 2>/dev/null || echo "/tmp/volume_history_$$")
        tail -n "$max_size" "$history_file" > "$temp_file" 2>/dev/null
        mv "$temp_file" "$history_file" 2>/dev/null || {
            rm -f "$temp_file" 2>/dev/null
            return 1
        }
    fi
}

load_volume_history() {
    local history_file
    history_file=$(get_volume_history_file)

    if [[ ! -f "$history_file" ]]; then
        return 0
    fi

    # Read history into array (format: volume|node_id|timestamp)
    local -a history_array=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        history_array+=("$line")
    done < "$history_file"

    # Return history as newline-separated string
    printf '%s\n' "${history_array[@]}"
}

get_last_volume_from_history() {
    local history_file
    history_file=$(get_volume_history_file)

    if [[ ! -f "$history_file" ]]; then
        return 1
    fi

    # Get the last entry for current node (or any node if current not found)
    local last_entry current_node_entry
    last_entry=$(tail -n 1 "$history_file" 2>/dev/null)

    if empty "$last_entry"; then
        return 1
    fi

    # Try to find last entry for current node
    if not_empty "$NODE_ID"; then
        current_node_entry=$(grep "|${NODE_ID}|" "$history_file" 2>/dev/null | tail -n 1)
        if not_empty "$current_node_entry"; then
            last_entry=$current_node_entry
        fi
    fi

    # Extract volume (first field)
    echo "$last_entry" | cut -d'|' -f1
}

get_last_history_entry_line() {
    local history_file
    history_file=$(get_volume_history_file)

    if [[ ! -f "$history_file" ]]; then
        return 1
    fi

    # Get the last entry for current node (or any node if current not found)
    local last_entry current_node_entry
    last_entry=$(tail -n 1 "$history_file" 2>/dev/null)

    if empty "$last_entry"; then
        return 1
    fi

    # Try to find last entry for current node
    if not_empty "$NODE_ID"; then
        current_node_entry=$(grep "|${NODE_ID}|" "$history_file" 2>/dev/null | tail -n 1)
        if not_empty "$current_node_entry"; then
            last_entry=$current_node_entry
        fi
    fi

    # Return the full entry line
    echo "$last_entry"
}

undo_volume() {
    local last_entry
    last_entry=$(get_last_history_entry_line)

    if empty "$last_entry"; then
        error "No volume history available to undo."
        echo "  ${COLOR_YELLOW}→${COLOR_RESET} Use 'volume history' to see recent changes."
        EXITCODE=$EX_USAGE
        return 1
    fi

    # Extract volume from the entry
    local last_vol
    last_vol=$(echo "$last_entry" | cut -d'|' -f1)

    # Get current volume to save before undo (so undo can be undone)
    local current_vol
    current_vol=$(get_volume 2>/dev/null || echo "0")

    # Remove the entry we're restoring to BEFORE saving current volume
    # This prevents infinite undo loops
    local history_file
    history_file=$(get_volume_history_file)
    if [[ -f "$history_file" ]]; then
        # Remove the specific entry we're restoring to
        local temp_file
        temp_file=$(mktemp 2>/dev/null || echo "/tmp/volume_history_$$")
        # Use grep -v to remove the specific line, handling it carefully
        if not_empty "$NODE_ID"; then
            # Remove last matching entry for current node
            grep -v "^${last_entry}$" "$history_file" > "$temp_file" 2>/dev/null || {
                # Fallback: remove last line
                head -n -1 "$history_file" > "$temp_file" 2>/dev/null
            }
        else
            # Remove last matching entry
            grep -v "^${last_entry}$" "$history_file" > "$temp_file" 2>/dev/null || {
                # Fallback: remove last line
                head -n -1 "$history_file" > "$temp_file" 2>/dev/null
            }
        fi
        if [[ -s "$temp_file" ]]; then
            mv "$temp_file" "$history_file" 2>/dev/null || {
                rm -f "$temp_file" 2>/dev/null
            }
        else
            rm -f "$history_file" "$temp_file" 2>/dev/null
        fi
    fi

    # Save current volume to history (after removing the entry we're restoring to)
    # This allows undo to be undone
    save_volume_to_history "$current_vol"

    # Set volume to the previous value
    invalidate_cache
    if not_empty "$FADE_DURATION"; then
        fade_volume "$last_vol" "$FADE_DURATION" "$NODE_ID"
    else
        wpctl set-volume "$NODE_ID" "${last_vol}%" &>/dev/null
        invalidate_cache
    fi
}

show_volume_history() {
    local history_file max_entries
    history_file=$(get_volume_history_file)
    max_entries=${1:-10}

    if [[ ! -f "$history_file" ]] || [[ ! -s "$history_file" ]]; then
        echo "No volume history available."
        return 0
    fi

    local count=0
    local current_node_id="${NODE_ID:-default}"

    echo "Volume History (showing last $max_entries entries):"
    echo ""

    # Read history in reverse (newest first) and filter by current node if available
    local -a relevant_entries=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        local entry_node_id
        entry_node_id=$(echo "$line" | cut -d'|' -f2)
        # Include entries for current node, or all if no specific node
        if [[ "$current_node_id" == "default" ]] || [[ "$entry_node_id" == "$current_node_id" ]]; then
            relevant_entries+=("$line")
        fi
    done < "$history_file"

    # Reverse array to show newest first
    local i
    for (( i=${#relevant_entries[@]}-1; i>=0 && count<max_entries; i-- )); do
        local entry="${relevant_entries[$i]}"
        local vol node_id timestamp
        IFS='|' read -r vol node_id timestamp <<< "$entry"

        # Format timestamp
        local date_str
        if [[ "$timestamp" =~ ^[0-9]+$ ]] && [[ "$timestamp" -gt 0 ]]; then
            # Try GNU date format first (Linux)
            date_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || \
                       # Try BSD date format (macOS)
                       date -r "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || \
                       echo "unknown")
        else
            date_str="unknown"
        fi

        # Show node name if available
        local node_display
        if [[ "$node_id" != "default" ]] && not_empty "$NODE_NAME"; then
            node_display=" ($NODE_NAME)"
        else
            node_display=""
        fi

        printf "  %3d%%%s - %s\n" "$vol" "$node_display" "$date_str"
        ((count++))
    done

    if (( count == 0 )); then
        echo "No history entries for current sink."
    fi
}

listen() {
    local args_str="$*"
    local -a args
    IFS=' ' read -ra args <<< "$args_str"

    # Parse options
    local monitor_all=false
    local monitor_input=false
    local watch_mode=false
    local volume_only=false
    local mute_only=false
    local output_format=""

    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
            -a|--all)
                monitor_all=true
                ;;
            -I|--input)
                monitor_input=true
                ;;
            --watch)
                watch_mode=true
                ;;
            --volume-only)
                volume_only=true
                ;;
            --mute-only)
                mute_only=true
                ;;
            -*)
                # Unknown option, skip
                ;;
            *)
                # Assume it's an output format
                if empty "$output_format"; then
                    output_format="${args[$i]}"
                fi
                ;;
        esac
        ((i++))
    done

    # Determine which nodes to monitor
    local -a node_ids
    local -a node_names
    local -a node_types

    if [[ "$monitor_input" == "true" ]]; then
        # Monitor input sources
        local -a sources
        readarray -t sources < <(pw_dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node" and .info.props."media.class" == "Audio/Source") | "\(.id)|\(.info.props."node.name")"' 2>/dev/null)
        for source in "${sources[@]}"; do
            IFS='|' read -r source_id source_name <<< "$source"
            node_ids+=("$source_id")
            node_names+=("$source_name")
            node_types+=("source")
        done
    elif [[ "$monitor_all" == "true" ]]; then
        # Monitor all sinks
        readarray -t node_ids < <(get_all_sinks)
        for sink_id in "${node_ids[@]}"; do
            local sink_name
            sink_name=$(pw_dump | jq -r --argjson id "$sink_id" '.[] | select(.id == $id) | .info.props."node.name"' 2>/dev/null)
            node_names+=("$sink_name")
            node_types+=("sink")
        done
    else
        # Monitor default sink only
        local default_sink_id
        default_sink_id=$(get_default_sink_id)
        if not_empty "$default_sink_id"; then
            node_ids+=("$default_sink_id")
            local sink_name
            sink_name=$(pw_dump | jq -r --argjson id "$default_sink_id" '.[] | select(.id == $id) | .info.props."node.name"' 2>/dev/null)
            node_names+=("$sink_name")
            node_types+=("sink")
        else
            error "No default sink found"
            return 1
        fi
    fi

    if [[ ${#node_ids[@]} -eq 0 ]]; then
        error "No nodes to monitor"
        return 1
    fi

    # Initialize state tracking
    local -A prev_volumes
    local -A prev_muted

    # Get initial state
    local i
    for i in "${!node_ids[@]}"; do
        local node_id="${node_ids[$i]}"
        local vol muted
        vol=$(wpctl get-volume "$node_id" 2>/dev/null | awk '{printf "%.2f", $2 * 100}' || echo "0")
        muted=$(wpctl get-volume "$node_id" 2>/dev/null | grep -q '\[MUTED\]' && echo "true" || echo "false")
        prev_volumes["$node_id"]="$vol"
        prev_muted["$node_id"]="$muted"
    done

    # Output initial state if in watch mode
    if [[ "$watch_mode" == "true" ]]; then
        for i in "${!node_ids[@]}"; do
            local node_id="${node_ids[$i]}"
            local node_name="${node_names[$i]}"
            local node_type="${node_types[$i]}"
            local vol="${prev_volumes[$node_id]}"
            local muted="${prev_muted[$node_id]}"

            local display_name
            if isset NODE_ALIASES["$node_id"]; then
                display_name="${NODE_ALIASES[$node_id]}"
            elif isset NODE_ALIASES["$node_name"]; then
                display_name="${NODE_ALIASES[$node_name]}"
            else
                display_name=$(pw_dump | jq -r --argjson id "$node_id" '.[] | select(.id == $id) | .info.props."node.nick" // .info.props."node.name"' 2>/dev/null)
            fi

            printf "[%s] %s: %s%% %s\n" "$node_type" "$display_name" "$vol" "$([ "$muted" == "true" ] && echo "[MUTED]" || echo "")"
        done
    fi

    # Main monitoring loop
    while true; do
        # Invalidate cache to get fresh data
        invalidate_cache

        # Check each node for changes
        for i in "${!node_ids[@]}"; do
            local node_id="${node_ids[$i]}"
            local node_name="${node_names[$i]}"
            local node_type="${node_types[$i]}"

            # Get current state
            local vol muted vol_changed mute_changed
            vol=$(wpctl get-volume "$node_id" 2>/dev/null | awk '{printf "%.2f", $2 * 100}' || echo "0")
            muted=$(wpctl get-volume "$node_id" 2>/dev/null | grep -q '\[MUTED\]' && echo "true" || echo "false")

            # Check for changes
            vol_changed=false
            mute_changed=false

            # Use decimal comparison for volume
            if [ "$(echo "$vol != ${prev_volumes[$node_id]}" | bc -l 2>/dev/null)" = "1" ]; then
                vol_changed=true
            fi

            if [[ "$muted" != "${prev_muted[$node_id]}" ]]; then
                mute_changed=true
            fi

            # Determine if we should output
            local should_output=false
            if [[ "$volume_only" == "true" ]] && [[ "$vol_changed" == "true" ]]; then
                should_output=true
            elif [[ "$mute_only" == "true" ]] && [[ "$mute_changed" == "true" ]]; then
                should_output=true
            elif [[ "$volume_only" != "true" ]] && [[ "$mute_only" != "true" ]] && ([[ "$vol_changed" == "true" ]] || [[ "$mute_changed" == "true" ]]); then
                should_output=true
            fi

            if [[ "$should_output" == "true" ]]; then
                # Temporarily set NODE_ID for output functions
                local saved_node_id="$NODE_ID"
                local saved_node_name="$NODE_NAME"
                NODE_ID="$node_id"
                NODE_NAME="$node_name"

                # Output based on format
                if not_empty "$output_format"; then
                    case "$output_format" in
                        i3blocks)
                            output_volume_i3blocks
                            ;;
                        *)
                            # Custom format or plugin
                            if is_output_plugin_available "$output_format"; then
                                call_output_plugin "$output_format"
                            else
                                output_volume_custom "$output_format"
                            fi
                            ;;
                    esac
                elif [[ "$watch_mode" == "true" ]]; then
                    # Terminal output in watch mode
                    local display_name
                    if isset NODE_ALIASES["$node_id"]; then
                        display_name="${NODE_ALIASES[$node_id]}"
                    elif isset NODE_ALIASES["$node_name"]; then
                        display_name="${NODE_ALIASES[$node_name]}"
                    else
                        display_name=$(pw_dump | jq -r --argjson id "$node_id" '.[] | select(.id == $id) | .info.props."node.nick" // .info.props."node.name"' 2>/dev/null)
                    fi

                    local change_info=""
                    if [[ "$vol_changed" == "true" ]]; then
                        change_info="volume: ${prev_volumes[$node_id]}% -> $vol%"
                    fi
                    if [[ "$mute_changed" == "true" ]]; then
                        if [[ -n "$change_info" ]]; then
                            change_info="$change_info, "
                        fi
                        change_info="${change_info}mute: ${prev_muted[$node_id]} -> $muted"
                    fi

                    printf "[%s] %s: %s\n" "$node_type" "$display_name" "$change_info"
                else
                    # Default: output in default format
                    output_volume_default
                fi

                # Restore NODE_ID
                NODE_ID="$saved_node_id"
                NODE_NAME="$saved_node_name"
            fi

            # Update previous state
            prev_volumes["$node_id"]="$vol"
            prev_muted["$node_id"]="$muted"
        done

        # Sleep before next check (100ms polling interval)
        sleep 0.1
    done
}
