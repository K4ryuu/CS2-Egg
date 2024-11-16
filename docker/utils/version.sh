#!/bin/bash
VERSION_FILE="./game/versions.txt"
SERVER_RUNNING=0

start_update_countdown() {
    local required_version="$1"
    local start_time=$(date +%s)

    # Validate variables first
    if [ -z "$PTERODACTYL_API_TOKEN" ] || [ -z "$P_SERVER_UUID" ] || [ -z "$PTERODACTYL_URL" ]; then
        log_message "Missing required API variables" "error"
        return 1
    fi

    if [ -z "$UPDATE_COMMANDS" ] || [ -z "$UPDATE_COUNTDOWN_TIME" ]; then
        log_message "Missing update configuration variables" "error"
        return 1
    fi

    local commands=$(echo "$UPDATE_COMMANDS" | jq -r 'to_entries | .[] | .key + " " + .value')

    while IFS=' ' read -r seconds command || [ -n "$seconds" ]; do
        if [ "$seconds" -gt "$UPDATE_COUNTDOWN_TIME" ]; then
            continue
        fi

        # Calculate wait time from start
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
                return 1
            fi
        fi
    done <<< "$commands"

	log_message "Restarting server by Auto-Restart..." "running"

    # Server restart when countdown reaches 0
    local restart_response=$(curl -s -w "%{http_code}" "$PTERODACTYL_URL/api/client/servers/$P_SERVER_UUID/power" \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
        -X POST \
        -d '{"signal": "restart"}')

    local restart_code=${restart_response: -3}
    if [[ $restart_code -lt 200 || $restart_code -gt 299 ]]; then
        log_message "Failed to restart server: HTTP $restart_code" "error"
        return 1
    fi
}

check_server_version() {
    VERSION_FILE="./version.txt"
    local current_version=""

    if [ -f "$VERSION_FILE" ]; then
        current_version=$(cat "$VERSION_FILE")
        response=$(curl -s "https://api.steampowered.com/ISteamApps/UpToDateCheck/v0001/?appid=730&version=$current_version")
        up_to_date=$(echo "$response" | grep -o '"up_to_date":false\|"up_to_date":true' | cut -d':' -f2)

        if [ "$up_to_date" = "false" ]; then
            required_version=$(echo "$response" | grep -o '"required_version":[0-9]*' | cut -d':' -f2)
            log_message "New version detected: $required_version (current: $current_version)" "running"
			log_message "Countdown initiated to restart server: $UPDATE_COUNTDOWN_TIME seconds" "running"

            if [ ! -z "$UPDATE_COMMANDS" ]; then
                start_update_countdown "$required_version"
            fi
        fi
    else
        log_message "Version file not found" "error"
    fi
}

version_check_loop() {
	local auto_restart=${UPDATE_AUTO_RESTART:-0}
	while [ $auto_restart -eq 1 ] && [ $SERVER_RUNNING -eq 1 ]; do
		sleep "${VERSION_CHECK_INTERVAL:-60}"
		check_server_version
	done
}