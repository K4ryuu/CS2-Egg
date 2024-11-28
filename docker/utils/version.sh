#!/bin/bash
UPDATE_IN_PROGRESS=0

start_update_countdown() {
    local required_version="$1"

    # Set update in progress flag
    UPDATE_IN_PROGRESS=1

    # Validate essential API variables
    if [ -z "$PTERODACTYL_API_TOKEN" ] || [ -z "$P_SERVER_UUID" ] || [ -z "$PTERODACTYL_URL" ]; then
        log_message "Missing required API variables" "error"
        UPDATE_IN_PROGRESS=0
        return 1
    fi

    if [ ! -z "$UPDATE_COMMANDS" ]; then
        local start_time=$(date +%s)
        local commands=$(echo "$UPDATE_COMMANDS" | jq -r 'to_entries | .[] | .key + " " + .value')

        while IFS=' ' read -r seconds command || [ -n "$seconds" ]; do
            if [ "$seconds" -gt "$UPDATE_COUNTDOWN_TIME" ]; then
                continue
            fi

            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local target_wait=$((UPDATE_COUNTDOWN_TIME - seconds))
            local wait_time=$((target_wait - elapsed))

            if [ "$wait_time" -gt 0 ]; then
                sleep $wait_time
            fi

            if [ -n "$command" ]; then
                local response=$(curl -s -w "%{http_code}" -X POST \
                    -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
                    -H "Content-Type: application/json" \
                    --data "{\"command\": \"$command\"}" \
                    "$PTERODACTYL_URL/api/client/servers/$P_SERVER_UUID/command")

                local http_code=${response: -3}
                if [[ $http_code -lt 200 || $http_code -gt 299 ]]; then
                    log_message "Failed to send command by Auto-Restart: HTTP $http_code" "error"
                    UPDATE_IN_PROGRESS=0
                    return 1
                fi
            fi
        done <<< "$commands"
    else
        sleep $UPDATE_COUNTDOWN_TIME
    fi

    log_message "Restarting server by Auto-Restart..." "running"

    # Server restart
    local restart_response=$(curl -s -w "%{http_code}" "$PTERODACTYL_URL/api/client/servers/$P_SERVER_UUID/power" \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
        -X POST \
        -d '{"signal": "restart"}')

    local restart_code=${restart_response: -3}
    if [[ $restart_code -lt 200 || $restart_code -gt 299 ]]; then
        log_message "Failed to restart server: HTTP $restart_code" "error"
        UPDATE_IN_PROGRESS=0
        return 1
    fi
}

get_game_version() {
    local steam_inf="./game/csgo/steam.inf"
    if [ -f "$steam_inf" ]; then
        local patch_version=$(grep "PatchVersion=" "$steam_inf" | cut -d'=' -f2)
        if [ ! -z "$patch_version" ]; then
            # Remove dots and convert to number (e.g., 1.40.5.1 -> 14051)
            echo "$patch_version" | tr -d '.'
            return 0
        fi
    fi
    return 1
}

check_server_version() {
    if [ "$UPDATE_IN_PROGRESS" -eq 1 ]; then
        return 0
    fi

    local current_version=$(get_game_version)

    if [ -z "$current_version" ]; then
        log_message "Failed to get game version from steam.inf" "error"
        return 1
    fi

    local api_url="https://api.steampowered.com/ISteamApps/UpToDateCheck/v0001/?appid=730&version=$current_version&nocache=$(date +%s)"
    local response=$(curl -s \
        -H "Cache-Control: no-cache, no-store" \
        -H "Pragma: no-cache" \
        "$api_url")

    local up_to_date=$(echo "$response" | jq -r '.response.up_to_date')

    if [ "$up_to_date" = "false" ]; then
        local required_version=$(echo "$response" | jq -r '.response.required_version')
        local message=$(echo "$response" | jq -r '.response.message')

        if [ ! -z "$required_version" ]; then
            log_message "New version detected: $required_version (current: $current_version)" "running"
            log_message "Steam message: $message" "running"

            if [ -z "$UPDATE_COUNTDOWN_TIME" ]; then
                UPDATE_COUNTDOWN_TIME=300
            fi

            log_message "Countdown initiated to restart server: $UPDATE_COUNTDOWN_TIME seconds" "running"

            if [ ! -z "$UPDATE_COMMANDS" ]; then
                start_update_countdown "$required_version"
            fi
        else
            log_message "Failed to get required version from API response" "error"
            log_message "Full response: $response" "debug"
            return 1
        fi
    else
        log_message "Server is up to date. Current version: $current_version (checked at: $(date '+%Y-%m-%d %H:%M:%S'))" "debug"
    fi
}

version_check_loop() {
    while [ ${UPDATE_AUTO_RESTART:-0} -eq 1 ] && [ $UPDATE_IN_PROGRESS -eq 0 ]; do
        sleep "${VERSION_CHECK_INTERVAL:-300}"
        check_server_version
    done
}