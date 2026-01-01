#!/bin/bash
#
# i3-volume - Helper Functions Module
#
# Utility functions and plugin system
#

# Utility functions
empty() { [[ -z $1 ]]; }
not_empty() { [[ -n $1 ]]; }
isset() { [[ -v $1 ]]; }
command_exists() { command -v "$1" &>/dev/null; }
# shellcheck disable=SC2034  # COLOR_RED and COLOR_RESET are external variables from main script
error() { echo "$COLOR_RED$*$COLOR_RESET"; }
error_with_suggestion() {
    local msg="$1"
    shift
    error "$msg"
    # shellcheck disable=SC2034  # COLOR_YELLOW and COLOR_RESET are external variables from main script
    while [[ $# -gt 0 ]]; do
        echo "  ${COLOR_YELLOW}→${COLOR_RESET} $1" >&2
        shift
    done
}
# shellcheck disable=SC2034  # DRY_RUN, COLOR_CYAN, and COLOR_RESET are external variables from main script
dry_run_msg() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "${COLOR_CYAN}[DRY-RUN]${COLOR_RESET} $*" >&2
    fi
}
has_color() { [ "$(tput colors)" -ge 8 ] &>/dev/null && [ -t 1 ]; }
ms_to_secs() { echo "scale=0; (${1} + 999) / 1000" | bc; }
# shellcheck disable=SC2034  # POST_HOOK_EXEMPT_COMMANDS is external variable from main script
is_command_hookable() { ! [[ ${POST_HOOK_EXEMPT_COMMANDS[*]} =~ $1 ]]; }
# shellcheck disable=SC2034  # NOTIFY_CAPS is external variable from main script
has_capability() { [[ "${NOTIFY_CAPS[*]}" =~ $1 ]]; }
max() { echo $(( $1 > $2 ? $1 : $2 )); }

# Decimal arithmetic functions for volume calculations
# These use bc for decimal precision (bc is a dependency)
decimal_add() {
    local a=$1
    local b=$2
    echo "$a + $b" | bc -l
}

decimal_subtract() {
    local a=$1
    local b=$2
    echo "$a - $b" | bc -l
}

decimal_multiply() {
    local a=$1
    local b=$2
    echo "$a * $b" | bc -l
}

decimal_divide() {
    local a=$1
    local b=$2
    echo "scale=2; $a / $b" | bc -l
}

# Compare two decimal values: returns 1 if true, 0 if false
# Usage: decimal_gt 45.5 45.0 -> returns 1 (true)
decimal_gt() {
    local a=$1
    local b=$2
    echo "$a > $b" | bc -l
}

decimal_lt() {
    local a=$1
    local b=$2
    echo "$a < $b" | bc -l
}

decimal_ge() {
    local a=$1
    local b=$2
    echo "$a >= $b" | bc -l
}

decimal_le() {
    local a=$1
    local b=$2
    echo "$a <= $b" | bc -l
}

decimal_eq() {
    local a=$1
    local b=$2
    echo "$a == $b" | bc -l
}

# Format decimal to specified precision (default 2 decimal places)
decimal_format() {
    local val=$1
    local precision=${2:-2}
    printf "%.${precision}f" "$val" 2>/dev/null || echo "$val"
}

# dB conversion functions (dBFS scale: 0dB = 100%, negative values for attenuation)
# Convert percentage to dB: dB = 20 * log10(percentage/100)
percentage_to_db() {
    local pct=$1
    # Handle edge cases: 0% = -120dB (effectively silent, avoid -infinity)
    if [ "$(echo "$pct <= 0" | bc -l 2>/dev/null)" = "1" ]; then
        echo "-120"
        return
    fi
    # Clamp to reasonable range to avoid issues
    if [ "$(echo "$pct > 100" | bc -l 2>/dev/null)" = "1" ]; then
        pct="100"
    fi
    # Calculate dB: 20 * log10(pct/100)
    echo "scale=2; 20 * l($pct / 100) / l(10)" | bc -l 2>/dev/null || echo "0"
}

# Convert dB to percentage: percentage = 100 * 10^(dB/20)
db_to_percentage() {
    local db=$1
    # Handle very negative dB (effectively 0%)
    if [ "$(echo "$db <= -120" | bc -l 2>/dev/null)" = "1" ]; then
        echo "0"
        return
    fi
    # Calculate percentage: 100 * 10^(dB/20)
    local result
    result=$(echo "scale=2; 100 * e($db / 20 * l(10))" | bc -l 2>/dev/null)
    # Clamp to 0-100 range
    if [ "$(echo "$result < 0" | bc -l 2>/dev/null)" = "1" ]; then
        echo "0"
    elif [ "$(echo "$result > 100" | bc -l 2>/dev/null)" = "1" ]; then
        echo "100"
    else
        echo "$result"
    fi
}

# Detect if volume value is in dB or percentage
# Returns: "db" or "percent"
detect_volume_unit() {
    local value=$1
    # Check if value ends with "dB" or "db" (case insensitive)
    if [[ "$value" =~ ^[+-]?[0-9]+\.?[0-9]*[dD][bB]$ ]]; then
        echo "db"
    else
        echo "percent"
    fi
}

# Parse volume value and return as percentage
# Handles both percentage and dB inputs
parse_volume_value() {
    local value=$1
    local unit
    unit=$(detect_volume_unit "$value")

    if [ "$unit" = "db" ]; then
        # Extract numeric part (remove "dB", "db", "DB", or "Db" suffix)
        # Use a simple approach: remove last 2 characters if they match dB pattern
        local db_value
        if [[ "$value" =~ ^(.+)[dD][bB]$ ]]; then
            db_value="${BASH_REMATCH[1]}"
        else
            db_value="$value"
        fi
        # Convert dB to percentage
        db_to_percentage "$db_value"
    else
        # Already in percentage, just return as-is
        echo "$value"
    fi
}

# Generalized plugin system for multiple plugin types
declare -gA LOADED_PLUGINS=()

get_script_dir() {
    # Get the directory where the volume script is located
    # Walk up the BASH_SOURCE stack to find the main volume script
    local i=0
    local script_path
    while [[ $i -lt ${#BASH_SOURCE[@]} ]]; do
        script_path="${BASH_SOURCE[$i]}"
        # If this is the main volume script (not a lib file), use it
        if [[ "$script_path" != *"/lib/"* ]] && [[ "$(basename "$script_path")" == "volume" ]]; then
            break
        fi
        ((i++))
    done

    # If we didn't find it, try to resolve from current file
    if [[ "$script_path" == *"/lib/"* ]] || [[ "$(basename "$script_path")" != "volume" ]]; then
        script_path="${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}"
        local dir
        dir=$(dirname "$script_path")
        if [[ "$dir" == *"/lib" ]]; then
            script_path="${dir%/lib}/volume"
        fi
    fi

    # Resolve symlinks
    if [[ -L "$script_path" ]]; then
        script_path=$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")
    fi

    dirname "$script_path"
}

get_plugin_dir() {
    local plugin_type=$1
    local base_dir="${XDG_CONFIG_HOME:-$HOME/.config}/i3-volume/plugins"
    echo "$base_dir/$plugin_type"
}

get_builtin_plugin_dir() {
    local plugin_type=$1
    local script_dir
    script_dir=$(get_script_dir)
    echo "$script_dir/plugins/$plugin_type"
}

load_plugin() {
    local plugin_type=$1
    local plugin_name=$2
    local plugin_key="${plugin_type}:${plugin_name}"

    # Check if plugin is already loaded
    [[ -v LOADED_PLUGINS["$plugin_key"] ]] && return 0

    local plugin_file
    # Check built-in plugins first (script-relative), then user plugins
    local builtin_dir
    builtin_dir=$(get_builtin_plugin_dir "$plugin_type")
    if [[ -f "$builtin_dir/$plugin_name" ]]; then
        plugin_file="$builtin_dir/$plugin_name"
    else
        local user_dir
        user_dir=$(get_plugin_dir "$plugin_type")
        plugin_file="$user_dir/$plugin_name"
    fi

    # Check if plugin file exists
    if [[ ! -f "$plugin_file" ]]; then
        return 1
    fi

    # Check if plugin file is executable
    if [[ ! -x "$plugin_file" ]]; then
        error "Plugin $plugin_name is not executable: $plugin_file"
        return 1
    fi

    # Source the plugin file
    # shellcheck source=/dev/null
    if source "$plugin_file" 2>/dev/null; then
        LOADED_PLUGINS["$plugin_key"]=1
        return 0
    else
        error "Failed to load plugin: $plugin_name"
        return 1
    fi
}

is_plugin_available() {
    local plugin_type=$1
    local plugin_name=$2
    local plugin_file
    # Check built-in plugins first (script-relative), then user plugins
    local builtin_dir
    builtin_dir=$(get_builtin_plugin_dir "$plugin_type")
    if [[ -f "$builtin_dir/$plugin_name" ]]; then
        plugin_file="$builtin_dir/$plugin_name"
    else
        local user_dir
        user_dir=$(get_plugin_dir "$plugin_type")
        plugin_file="$user_dir/$plugin_name"
    fi

    [[ -f "$plugin_file" && -x "$plugin_file" ]]
}

call_plugin() {
    local plugin_type=$1
    local plugin_name=$2
    shift 2
    local func_name="${plugin_type}_${plugin_name}"

    # Try to load plugin if not already loaded
    if ! load_plugin "$plugin_type" "$plugin_name"; then
        return 1
    fi

    # Check if the function exists
    if ! declare -f "$func_name" >/dev/null 2>&1; then
        error "Plugin $plugin_name does not define function: $func_name"
        return 1
    fi

    # Call the plugin function with all remaining arguments
    "$func_name" "$@"
}

list_plugins() {
    local plugin_type=$1
    local -A seen_plugins=()

    # List built-in plugins first (script-relative)
    local builtin_dir
    builtin_dir=$(get_builtin_plugin_dir "$plugin_type")
    if [[ -d "$builtin_dir" ]]; then
        local plugin_file
        while IFS= read -r -d '' plugin_file; do
            local plugin_name
            plugin_name=$(basename "$plugin_file")
            if [[ -x "$plugin_file" ]]; then
                echo "$plugin_name"
                seen_plugins["$plugin_name"]=1
            fi
        done < <(find "$builtin_dir" -maxdepth 1 -type f -executable -print0 2>/dev/null)
    fi

    # List user plugins (skip if already seen from built-ins)
    local user_dir
    user_dir=$(get_plugin_dir "$plugin_type")
    if [[ -d "$user_dir" ]]; then
        local plugin_file
        while IFS= read -r -d '' plugin_file; do
            local plugin_name
            plugin_name=$(basename "$plugin_file")
            if [[ -x "$plugin_file" ]] && [[ ! -v seen_plugins["$plugin_name"] ]]; then
                echo "$plugin_name"
            fi
        done < <(find "$user_dir" -maxdepth 1 -type f -executable -print0 2>/dev/null)
    fi
}

# Check if PipeWire is running
check_pipewire_running() {
    if ! command_exists pw-dump; then
        return 1
    fi
    if ! pw-dump &>/dev/null; then
        return 1
    fi
    return 0
}

# Check if wpctl is available and working
check_wpctl_available() {
    if ! command_exists wpctl; then
        return 1
    fi
    return 0
}

# Get diagnostic information for verbose mode
get_pipewire_diagnostics() {
    local diag=""
    if ! check_pipewire_running; then
        diag="PipeWire service may not be running. Try: systemctl --user status pipewire pipewire-pulse"
    elif ! check_wpctl_available; then
        diag="wpctl command not found. Install WirePlumber package."
    else
        # Try to get default sink info
        if ! wpctl inspect @DEFAULT_AUDIO_SINK@ &>/dev/null; then
            diag="Cannot access default audio sink. PipeWire may not be fully initialized."
        fi
    fi
    echo "$diag"
}

# Logging functions
# shellcheck disable=SC2034  # LOG_FILE, LOG_TO_SYSLOG, DEBUG_MODE are external variables from main script
init_logging() {
    # Initialize logging if --log option is provided
    if empty "${LOG_FILE:-}"; then
        return 0
    fi

    # If LOG_FILE is "syslog", use syslog
    if [[ "$LOG_FILE" == "syslog" ]]; then
        LOG_TO_SYSLOG=true
        return 0
    fi

    # Otherwise, use a custom log file
    LOG_TO_SYSLOG=false

    # Create log directory if it doesn't exist
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if not_empty "$log_dir" && [[ "$log_dir" != "." ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            error "Failed to create log directory: $log_dir"
            LOG_FILE=""
            return 1
        }
    fi

    # Create or append to log file
    if ! touch "$LOG_FILE" 2>/dev/null; then
        error "Failed to create log file: $LOG_FILE"
        LOG_FILE=""
        return 1
    fi

    return 0
}

# Log a message with timestamp
# Usage: log_message <level> <message>
# Levels: DEBUG, INFO, WARNING, ERROR
log_message() {
    local level=$1
    shift
    local message="$*"

    # Only log if logging is enabled
    if empty "${LOG_FILE:-}"; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "${LOG_TO_SYSLOG:-false}" == "true" ]]; then
        # Use logger for syslog
        local priority
        case "$level" in
            DEBUG) priority="debug" ;;
            INFO) priority="info" ;;
            WARNING) priority="warning" ;;
            ERROR) priority="err" ;;
            *) priority="info" ;;
        esac
        logger -t "i3-volume" -p "user.$priority" "$message" 2>/dev/null || true
    else
        # Write to log file
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Log debug message (only if --debug is enabled)
log_debug() {
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        log_message "DEBUG" "$@"
    fi
}

# Log info message
log_info() {
    log_message "INFO" "$@"
}

# Log warning message
log_warning() {
    log_message "WARNING" "$@"
}

# Log error message
log_error() {
    log_message "ERROR" "$@"
}

# Log command execution
log_command() {
    local cmd="$1"
    shift
    log_info "Command: $cmd" "$@"
    log_debug "Full command: $cmd ${*}"
}

# Log volume operation
log_volume_operation() {
    local operation=$1
    shift
    log_info "Volume operation: $operation" "$@"
}

