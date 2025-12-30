#!/bin/bash
#
# i3-volume - Configuration Module
#
# Configuration file loading and management
#

init_color() {
    has_color && {
        # These are global variables used across modules (set in main script, used by other modules)
        # shellcheck disable=SC2034  # COLOR_RESET used externally by modules
        declare -g COLOR_RESET=$'\033[0m'
        # shellcheck disable=SC2034  # COLOR_RED used externally by modules
        declare -g COLOR_RED=$'\033[0;31m'
        # shellcheck disable=SC2034  # COLOR_GREEN used externally by modules
        declare -g COLOR_GREEN=$'\033[0;32m'
        # shellcheck disable=SC2034  # COLOR_YELLOW used externally by modules
        declare -g COLOR_YELLOW=$'\033[0;33m'
        # shellcheck disable=SC2034  # COLOR_MAGENTA used externally by modules
        declare -g COLOR_MAGENTA=$'\033[0;35m'
        # shellcheck disable=SC2034  # COLOR_CYAN used externally by modules
        declare -g COLOR_CYAN=$'\033[0;36m'
    }
}

load_config() {
    local -r config=${XDG_CONFIG_HOME:-$HOME/.config}/i3-volume/config
    local config_dir
    config_dir=$(dirname "$config")

    if [[ ! -f "$config" ]]; then
        # Set defaults if no config file
        : "${NOTIFICATION_METHOD:=libnotify}"
        return 0
    fi

    # Process config file line by line to handle includes
    local processed_includes=()
    process_config_file() {
        local file_to_process=$1
        local file_dir
        file_dir=$(dirname "$file_to_process")

        # Prevent infinite loops from circular includes
        local file_abs
        file_abs=$(readlink -f "$file_to_process" 2>/dev/null || echo "$file_to_process")
        if [[ " ${processed_includes[*]} " =~ ${file_abs} ]]; then
            error "Circular include detected: $file_to_process"
            return 1
        fi
        processed_includes+=("$file_abs")

        while IFS= read -r line || [[ -n "$line" ]]; do
            local trimmed_line
            trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Skip empty lines and comments
            [[ -z "$trimmed_line" ]] && continue
            [[ "$trimmed_line" =~ ^# ]] && continue

            # Check for include directive
            if [[ "$trimmed_line" =~ ^source[[:space:]]+ ]] || [[ "$trimmed_line" =~ ^\.[[:space:]]+ ]]; then
                local include_file
                include_file=$(echo "$trimmed_line" | sed -E 's/^(source|\.)[[:space:]]+["'\'']?([^"'\'']+)["'\'']?.*/\2/')

                # Try relative to current file's directory first, then config directory
                local resolved_include=""
                if [[ -f "$file_dir/$include_file" ]]; then
                    resolved_include="$file_dir/$include_file"
                elif [[ -f "$config_dir/$include_file" ]]; then
                    resolved_include="$config_dir/$include_file"
                elif [[ -f "$include_file" ]]; then
                    resolved_include="$include_file"
                fi

                if [[ -n "$resolved_include" ]]; then
                    process_config_file "$resolved_include" || return 1
                else
                    error "Include file not found: $include_file"
                    return 1
                fi
            else
                # Regular config line - evaluate it
                eval "$line" 2>/dev/null || {
                    error "Error processing config line: $line"
                    return 1
                }
            fi
        done < "$file_to_process"
    }

    # Process main config file
    process_config_file "$config" || {
        error "Failed to load config file: $config"
        return 1
    }

    # Set defaults if not defined in config
    : "${NOTIFICATION_METHOD:=libnotify}"
}

save_config_value() {
    local -r key=$1
    local -r value=$2
    local -r config=${XDG_CONFIG_HOME:-$HOME/.config}/i3-volume/config
    local config_dir
    config_dir=$(dirname "$config")

    # Create config directory if it doesn't exist
    mkdir -p "$config_dir" || {
        error "Failed to create config directory: $config_dir"
        return 1
    }

    # Check if key already exists in config
    if [[ -f "$config" ]] && grep -q "^[[:space:]]*${key}=" "$config" 2>/dev/null; then
        # Update existing value
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS sed
            sed -i '' "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$config"
        else
            # GNU sed
            sed -i "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$config"
        fi
    else
        # Append new key-value pair
        echo "${key}=${value}" >> "$config"
    fi
}

# Get effective MAX_VOL for current sink (per-sink or global)
get_effective_max_vol() {
    if empty "$NODE_ID" || empty "$NODE_NAME"; then
        echo "${MAX_VOL:-100}"
        return 0
    fi

    # Check by ID first
    if isset "SINK_MAX_VOL[$NODE_ID]"; then
        echo "${SINK_MAX_VOL[$NODE_ID]}"
        return 0
    fi

    # Check by name
    if isset "SINK_MAX_VOL[$NODE_NAME]"; then
        echo "${SINK_MAX_VOL[$NODE_NAME]}"
        return 0
    fi

    # Check by nick
    if not_empty "$NODE_NICK" && isset "SINK_MAX_VOL[$NODE_NICK]"; then
        echo "${SINK_MAX_VOL[$NODE_NICK]}"
        return 0
    fi

    # Fall back to global value
    echo "${MAX_VOL:-100}"
}

# Get effective DEFAULT_STEP for current sink (per-sink or global)
get_effective_default_step() {
    if empty "$NODE_ID" || empty "$NODE_NAME"; then
        echo "${DEFAULT_STEP:-5}"
        return 0
    fi

    # Check by ID first
    if isset "SINK_DEFAULT_STEP[$NODE_ID]"; then
        echo "${SINK_DEFAULT_STEP[$NODE_ID]}"
        return 0
    fi

    # Check by name
    if isset "SINK_DEFAULT_STEP[$NODE_NAME]"; then
        echo "${SINK_DEFAULT_STEP[$NODE_NAME]}"
        return 0
    fi

    # Check by nick
    if not_empty "$NODE_NICK" && isset "SINK_DEFAULT_STEP[$NODE_NICK]"; then
        echo "${SINK_DEFAULT_STEP[$NODE_NICK]}"
        return 0
    fi

    # Fall back to global value
    echo "${DEFAULT_STEP:-5}"
}

# Get effective DISPLAY_NOTIFICATIONS for current sink (per-sink or global)
get_effective_display_notifications() {
    if empty "$NODE_ID" || empty "$NODE_NAME"; then
        echo "${DISPLAY_NOTIFICATIONS:-false}"
        return 0
    fi

    local value=""

    # Check by ID first
    if isset "SINK_DISPLAY_NOTIFICATIONS[$NODE_ID]"; then
        value="${SINK_DISPLAY_NOTIFICATIONS[$NODE_ID]}"
    # Check by name
    elif isset "SINK_DISPLAY_NOTIFICATIONS[$NODE_NAME]"; then
        value="${SINK_DISPLAY_NOTIFICATIONS[$NODE_NAME]}"
    # Check by nick
    elif not_empty "$NODE_NICK" && isset "SINK_DISPLAY_NOTIFICATIONS[$NODE_NICK]"; then
        value="${SINK_DISPLAY_NOTIFICATIONS[$NODE_NICK]}"
    # Fall back to global value
    else
        value="${DISPLAY_NOTIFICATIONS:-false}"
    fi

    # Convert to boolean string if needed
    if [[ "$value" == "true" ]] || [[ "$value" == "1" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

