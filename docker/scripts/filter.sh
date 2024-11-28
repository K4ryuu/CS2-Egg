#!/bin/bash
source /utils/logging.sh

setup_message_filter() {
    if [ "${ENABLE_FILTER:-0}" != "1" ]; then
        log_message "Filter is disabled. No messages will be blocked." "running"
        return 0
    fi

    # Create default config if not exists
    if [ ! -f "/home/container/game/mute_messages.cfg" ]; then
        cat > "/home/container/game/mute_messages.cfg" <<'EOL'
# Mute Messages Configuration File
# Prefix with @ for exact match, otherwise treated as contains
# Example: @exact match
# Example: contains this anywhere
Certificate expires
EOL
        log_message "Created default mute_messages.cfg" "running"
    fi

    # Pre-process patterns for better performance
    declare -gA EXACT_PATTERNS=()
    declare -gA CONTAINS_PATTERNS=()

    # Add Steam token to patterns if exists
    if [ ! -z "${STEAM_ACC}" ]; then
        CONTAINS_PATTERNS["${STEAM_ACC}"]="********************************"
    fi

    # Process config file
    local pattern_count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Process pattern
        if [[ $line == @* ]]; then
            # Exact match
            EXACT_PATTERNS["${line#@}"]="1"
        else
            # Contains match
            CONTAINS_PATTERNS["$line"]="1"
        fi
        ((pattern_count++))
    done < "./game/mute_messages.cfg"

    log_message "Loaded $pattern_count filter patterns (${#EXACT_PATTERNS[@]} exact, ${#CONTAINS_PATTERNS[@]} contains). Modify mute_messages.cfg to add more." "running"
}

handle_server_output() {
    local line="$1"

    # Early return for empty lines
    [[ -z "$line" ]] && {
        printf '%s\n' "$line"
        return
    }

    # Check for Steam connection success and start version check if needed
    if [[ "$line" == "SV:  Connection to Steam servers successful." && "${UPDATE_AUTO_RESTART:-0}" -eq 1 ]]; then
        log_message "Auto-Restart enabled. The server will be restarted on game update detection." "running"
        version_check_loop &
    fi

    # Skip filtering if disabled
    if [ "${ENABLE_FILTER:-0}" != "1" ]; then
        printf '%s\n' "$line"
        return
    fi

    # Check for matches
    local blocked=false
    local modified_line="$line"

    # Check exact matches first (faster)
    for pattern in "${!EXACT_PATTERNS[@]}"; do
        if [[ "$line" == "$pattern" ]]; then
            blocked=true
            break
        fi
    done

    # If not blocked, check contains patterns and do replacements
    if [[ "$blocked" == false ]]; then
        for pattern in "${!CONTAINS_PATTERNS[@]}"; do
            if [[ $line == *"$pattern"* ]]; then
                if [ -n "${CONTAINS_PATTERNS[$pattern]}" ] && [ "${CONTAINS_PATTERNS[$pattern]}" != "1" ]; then
                    # Replace pattern with mask
                    modified_line=${modified_line//$pattern/${CONTAINS_PATTERNS[$pattern]}}
                else
                    blocked=true
                    break
                fi
            fi
        done
    fi

    # Output handling
    if [[ "$blocked" == true ]]; then
        if [ "${FILTER_PREVIEW_MODE:-0}" = "1" ]; then
            log_message "Blocked message: $line" "debug"
        fi
    else
        printf '%s\n' "$modified_line"
    fi
}