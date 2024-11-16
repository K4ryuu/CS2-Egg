#!/bin/bash
source /utils/logging.sh

setup_message_filter() {
    if [ "$ENABLE_FILTER" = "1" ]; then
        if [ ! -f "./game/mute_messages.cfg" ]; then
            cat <<EOL > ./game/mute_messages.cfg
# Mute Messages Configuration File
# Add patterns of messages to be blocked.
# One line is one check. If the line is like "asd", then the message should be blocked if it equals "asd".
# If the line is like ".*asd.*", then block the message if the line contains "asd" with anything before or after.
# Example pattern to block messages containing "Certificate expires":
# .*Certificate expires.*

.*Certificate expires.*
EOL
            log_message "Created ./game/mute_messages.cfg with example patterns. You can modify this file to specify additional messages to mute." "running"
        else
            log_message "./game/mute_messages.cfg already exists. You can modify this file to specify additional messages to mute." "success"
        fi

        BASIC_PATTERNS=()
        USER_PATTERNS=()

        while IFS= read -r pattern || [[ -n "$pattern" ]]; do
            [[ $pattern =~ ^#.*$ ]] && continue
            [[ -z "$pattern" ]] && continue
            USER_PATTERNS+=("$pattern")
        done < ./game/mute_messages.cfg

        log_message "Loaded ${#USER_PATTERNS[@]} user-defined patterns from ./game/mute_messages.cfg" "running"

        MUTE_PATTERNS=()
        if [ ${#BASIC_PATTERNS[@]} -gt 0 ]; then
            MUTE_PATTERNS=("${BASIC_PATTERNS[@]}")
        fi
        if [ ${#USER_PATTERNS[@]} -gt 0 ]; then
            MUTE_PATTERNS+=("${USER_PATTERNS[@]}")
        fi

        MUTE_PATTERNS=("${MUTE_PATTERNS[@]}")
    else
        log_message "Filter is disabled. No messages will be blocked." "running"
    fi
}

handle_server_output() {
    local line="$1"
    local server_stopped=false

    # Check for server running status
    if [[ "$line" == *"Connection to Steam servers successful."* ]]; then
        SERVER_RUNNING=1

        if [ "$UPDATE_AUTO_RESTART" -eq 1 ]; then
            if [ -z "$PTERODACTYL_API_TOKEN" ]; then
                log_message "Version check feature is enabled but PTERODACTYL_API_TOKEN is not set." "error"
                log_message "You can create a new token here: ${PTERODACTYL_URL}/account/api" "error"
                UPDATE_AUTO_RESTART=0
                return 1
            fi

            version_check_loop &
            log_message "Version check feature is enabled. The server will be restarted automatically if a new version is detected." "success"
        fi
    fi

    if [ "$server_stopped" = true ]; then
        log_message "The server is shutting down..." "success"
        server_stopped=true
        SERVER_RUNNING=0
    fi

    # Mask the specific Steam token if it matches the given variable
    if [[ "$line" =~ ($STEAM_ACC) ]]; then
        line=${line//${BASH_REMATCH[1]}/${BASH_REMATCH[1]//?/*}}
    fi

    if [ "$ENABLE_FILTER" = "1" ]; then
        BLOCKED=false
        for pattern in "${MUTE_PATTERNS[@]}"; do
            if [[ $line =~ $pattern ]]; then
                if [ "$FILTER_PREVIEW_MODE" = "1" ]; then
                    log_message "Message Block Preview: $line" "error"
                fi
                BLOCKED=true
                break
            fi
        done
        if [ "$BLOCKED" = false ] && [ -n "$line" ]; then
            printf '%s\n' "$line"
        fi
    else
        if [ -n "$line" ]; then
            printf '%s\n' "$line"
        fi
    fi
}