#!/bin/bash

LAST_NEWS_DATE=0
UPDATE_IN_PROGRESS=0

start_update_countdown() {
    local required_version="$1"

    UPDATE_IN_PROGRESS=1

    if [ -z "$PTERODACTYL_API_TOKEN" ] || [ -z "$P_SERVER_UUID" ] || [ -z "$PTERODACTYL_URL" ]; then
        log_message "Missing required API variables" "error"
        UPDATE_IN_PROGRESS=0
        return 1
    fi

    if [ -n "$UPDATE_COMMANDS" ]; then
        local start_time
        start_time=$(date +%s)
        local commands

        commands=$(echo "$UPDATE_COMMANDS" | jq -r 'to_entries | .[] | .key + " " + .value')

        while IFS=' ' read -r seconds command || [ -n "$seconds" ]; do
            if [ "$seconds" -gt "$UPDATE_COUNTDOWN_TIME" ]; then
                continue
            fi

            local current_time elapsed target_wait wait_time
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            target_wait=$((UPDATE_COUNTDOWN_TIME - seconds))
            wait_time=$((target_wait - elapsed))

            if [ "$wait_time" -gt 0 ]; then
                sleep "$wait_time"
            fi

            if [ -n "$command" ]; then
                local response
                response=$(curl -s -w "%{http_code}" -X POST \
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

                log_message "Sent command by Auto-Restart: $command" "running"
            fi
        done <<< "$commands"

    else
        sleep "$UPDATE_COUNTDOWN_TIME"
    fi

    log_message "Restarting server by Auto-Restart..." "running"

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

send_discord_webhook() {
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        return 0
    fi

    local patch_date="$1"
    local countdown_time="$2"

    local formatted_date
    formatted_date=$(date -d @"$patch_date" "+%Y-%m-%d %H:%M:%S")

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

check_for_new_patchnotes() {
    if [ "$UPDATE_IN_PROGRESS" -eq 1 ]; then
        return 0
    fi

    if [ -z "$STEAM_API_KEY" ]; then
        log_message "STEAM_API_KEY is not set. Cannot check for game updates." "error"
        return 1
    fi

    local steam_api_url
    steam_api_url="http://api.steampowered.com/ISteamNews/GetNewsForApp/v0002/?appid=730&count=1&maxlength=300&format=json&tags=patchnotes&key=$STEAM_API_KEY"
    local response
    response=$(curl -s "$steam_api_url")

    if [ -z "$response" ]; then
        log_message "No response from Steam API." "error"
        return 1
    fi

    local news_date
    news_date=$(echo "$response" | jq -r '.appnews.newsitems[0].date // 0')
    if [ "$news_date" -eq 0 ]; then
        log_message "Failed to extract valid date from Steam API response." "error"
        return 1
    fi

    if [ "$LAST_NEWS_DATE" -eq 0 ]; then
        LAST_NEWS_DATE="$news_date"
        log_message "Initial patch data stored: $news_date" "debug"
        return 0
    fi

    if [ "$news_date" -gt "$LAST_NEWS_DATE" ]; then
        log_message "New game patch detected: $news_date" "info"
        log_message "Starting update countdown..." "info"

        send_discord_webhook "$news_date" "$UPDATE_COUNTDOWN_TIME"

        local required_version="$news_date"
        start_update_countdown "$required_version"

        LAST_NEWS_DATE="$news_date"
    fi
}

version_check_loop() {
    if [ -z "$VERSION_CHECK_INTERVAL" ] || [ "$VERSION_CHECK_INTERVAL" -lt 60 ]; then
        VERSION_CHECK_INTERVAL=60
        log_message "VERSION_CHECK_INTERVAL is not set or less than 1 minute. Using default value: 1 minute" "warning"
    fi

    while [ "${UPDATE_AUTO_RESTART:-0}" -eq 1 ] && [ "$UPDATE_IN_PROGRESS" -eq 0 ]; do
        sleep "${VERSION_CHECK_INTERVAL}"
        check_for_new_patchnotes
    done
}