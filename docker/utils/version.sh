#!/bin/bash

LAST_BUILDID=0
UPDATE_IN_PROGRESS=0

# Grab the latest buildid straight from Steam's API
# Way cleaner than running SteamCMD every time
check_game_version_api() {
    local app_id="${SRCDS_APPID:-730}"
    local branch="${SRCDS_BETAID:-public}"
    local api_url="https://api.steamcmd.net/v1/info/${app_id}"

    log_message "Checking for updates via Steam API..." "debug"

    local response
    response=$(curl -sf --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log_message "Failed to reach Steam API" "warning"
        return 1
    fi

    local buildid
    buildid=$(echo "$response" | jq -r ".data.\"${app_id}\".depots.branches.${branch}.buildid" 2>/dev/null)

    if [ -z "$buildid" ] || [ "$buildid" = "null" ]; then
        log_message "Failed to parse buildid from API response" "error"
        return 1
    fi

    echo "$buildid"
    return 0
}

# Check what version we're currently running
get_current_buildid() {
    local buildid_file="/home/container/game/csgo/steam.inf"
    local buildid

    if [ -f "$buildid_file" ]; then
        buildid=$(sed -n 's/^PatchVersion=\([0-9]\+\)/\1/p' "$buildid_file" 2>/dev/null)
        if [ -z "$buildid" ]; then
            buildid=$(sed -n 's/^ClientVersion=\([0-9]\+\)/\1/p' "$buildid_file" 2>/dev/null)
        fi
    fi

    echo "$buildid"
}

start_update_countdown() {
    local required_version="$1"

    UPDATE_IN_PROGRESS=1

    # Make sure we have all the API creds before trying anything
    if [ -z "$PTERODACTYL_API_TOKEN" ] || [ -z "$P_SERVER_UUID" ] || [ -z "$PTERODACTYL_URL" ]; then
        log_message "API configuration missing, cannot restart" "error"
        UPDATE_IN_PROGRESS=0
        return 1
    fi

    # Run countdown commands if they're configured
    if [ -n "$UPDATE_COMMANDS" ]; then
        local start_time
        start_time=$(date +%s)
        local commands

        commands=$(echo "$UPDATE_COMMANDS" | jq -r 'to_entries | .[] | .key + " " + .value')

        while IFS=' ' read -r seconds command || [ -n "$seconds" ]; do
            if [ "$seconds" -gt "$UPDATE_COUNTDOWN_TIME" ]; then
                continue
            fi

            # Calculate how long to wait before sending this command
            local current_time elapsed target_wait wait_time
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            target_wait=$((UPDATE_COUNTDOWN_TIME - seconds))
            wait_time=$((target_wait - elapsed))

            if [ "$wait_time" -gt 0 ]; then
                sleep "$wait_time"
            fi

            # Send the command via Pterodactyl API
            if [ -n "$command" ]; then
                local response
                response=$(curl -s -w "%{http_code}" -X POST \
                    -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
                    -H "Content-Type: application/json" \
                    --data "{\"command\": \"$command\"}" \
                    "$PTERODACTYL_URL/api/client/servers/$P_SERVER_UUID/command")

                local http_code=${response: -3}
                if [[ $http_code -lt 200 || $http_code -gt 299 ]]; then
                    log_message "Command failed (HTTP $http_code): $command" "error"
                    UPDATE_IN_PROGRESS=0
                    return 1
                fi

                log_message "Executed: $command" "debug"
            fi
        done <<< "$commands"

    else
    # No commands configured, just wait out the countdown
        sleep "$UPDATE_COUNTDOWN_TIME"
    fi

    log_message "Restarting server to apply update..." "running"

    # Trigger the actual restart via API
    local restart_response
    restart_response=$(curl -s -w "%{http_code}" "$PTERODACTYL_URL/api/client/servers/$P_SERVER_UUID/power" \
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

# Send a fancy Discord notification if webhook is configured
send_discord_webhook() {
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        return 0
    fi

    local patch_date="$1"
    local countdown_time="$2"

    local formatted_date
    # Use -r for portability (works on both GNU and BSD date)
    if date -r "$patch_date" "+%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
        formatted_date=$(date -r "$patch_date" "+%Y-%m-%d %H:%M:%S")
    else
        # Fallback for GNU date
        formatted_date=$(date -d @"$patch_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown")
    fi

    local timestamp
    timestamp=$(date +%Y-%m-%dT%H:%M:%SZ)

    local payload
    payload=$(cat <<EOF
{
  "username": "Auto Restart",
  "avatar_url": "https://kitsune-lab.com/storage/images/server.png",
  "embeds": [
    {
      "title": ":warning: Server Update Scheduled :warning:",
      "description": "New game patch detected. Initiating update countdown...",
      "color": 16753920,
      "fields": [
        {
          "name": ":calendar: Patch Date",
          "value": "$formatted_date",
          "inline": true
        },
        {
          "name": ":hourglass: Countdown",
          "value": "$countdown_time seconds",
          "inline": true
        }
      ],
      "footer": {
        "text": "Auto Restart Service"
      },
      "timestamp": "$timestamp"
    }
  ]
}
EOF
)
    local response http_code
    response=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK_URL")
    http_code="${response: -3}"

    if [ "$http_code" -lt 200 ] || [ "$http_code" -gt 299 ]; then
        log_message "Failed to send Discord webhook: HTTP $http_code" "error"
    fi
}

# Main function to check if there's a new update available
check_for_new_updates() {
    if [ "$UPDATE_IN_PROGRESS" -eq 1 ]; then
        return 0
    fi
    
    local current_buildid
    local latest_buildid
    
    current_buildid=$(get_current_buildid)
    
    # Store the initial buildid on first run
    if [ "$LAST_BUILDID" -eq 0 ] && [ -n "$current_buildid" ]; then
        LAST_BUILDID="$current_buildid"
        log_message "Stored initial buildid: $LAST_BUILDID" "debug"
    fi
    
    latest_buildid=$(check_game_version_api)
    
    # If we got a new buildid and it's different, time to update
    if [ $? -eq 0 ] && [ -n "$latest_buildid" ] && [ "$latest_buildid" != "$LAST_BUILDID" ]; then
        log_message "CS2 update detected: BuildID $latest_buildid (current: $LAST_BUILDID)" "info"
        
        send_discord_webhook "$(date +%s)" "$UPDATE_COUNTDOWN_TIME"
        
        start_update_countdown "$latest_buildid"
        
        LAST_BUILDID="$latest_buildid"
        return 0
    fi
    
    return 1
}

# Keep checking for updates in a loop
version_check_loop() {
    # Prefer config value, fall back to env var if not set
    local check_interval="${RESTART_CHECK_INTERVAL:-${VERSION_CHECK_INTERVAL:-300}}"
    
    # Don't let people spam the API every second lol
    if [ "$check_interval" -lt 60 ]; then
        check_interval=60
        log_message "Check interval too low, using minimum: 60s" "warning"
    fi

    while [ "${AUTO_UPDATE:-${UPDATE_AUTO_RESTART:-0}}" -eq 1 ] && [ "$UPDATE_IN_PROGRESS" -eq 0 ]; do
        sleep "$check_interval"
        check_for_new_updates
    done
}