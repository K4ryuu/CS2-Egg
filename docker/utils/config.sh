#!/bin/bash

source /utils/logging.sh

# Current config version - bump this when adding new fields
CONFIG_VERSION="1.0.0"

# Use organized egg directory structure
CONFIG_DIR="${EGG_CONFIGS_DIR:-/home/container/egg/configs}"

# Migrate old config to new version
migrate_config() {
    local config_file="$1"
    local config_name="$2"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
  # Check if version field exists and matches
  local current_version=$(jq -r '.version // "0.0.0"' "$config_file" 2>/dev/null)
    
    if [ "$current_version" == "$CONFIG_VERSION" ]; then
        return 0
    fi
    
    log_message "Migrating $config_name from v$current_version to v$CONFIG_VERSION" "debug"
    
    # Extract old values
    local old_values=$(jq -r 'del(._description) | del(.version)' "$config_file" 2>/dev/null)
    
    # Remove old config
    rm "$config_file"
    
    # Return the old values so we can merge them
    echo "$old_values"
}

init_configs() {
  # Initialize egg directories (from logging.sh)
    init_egg_directories

    mkdir -p "$CONFIG_DIR"

    create_auto_restart_config
    create_webhook_config
    create_console_filter_config
    create_cleanup_config
    create_logging_config

    log_message "Configuration initialized" "success"
}

create_auto_restart_config() {
    local config_file="$CONFIG_DIR/auto-restart.json"
    local old_values=""

  # Migrate if needed
    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "auto-restart")
    fi

    if [ ! -f "$config_file" ]; then
        log_message "Creating default auto-restart config..." "debug"
        cat > "$config_file" << 'EOF'
{
  "version": "1.0.0",
  "_description": [
    "Auto-Restart Configuration",
    "",
    "This configuration controls the automatic server restart behavior when CS2 updates are detected.",
    "",
    "Settings:",
    "  - check_interval: How often to check for updates (in seconds, minimum 60)",
    "  - countdown_time: How long to wait before restarting after update detected (in seconds)",
    "  - commands: Console commands to execute at specific countdown intervals",
    "",
    "API Configuration:",
    "  - pterodactyl_url: Your Pterodactyl panel URL (e.g., https://panel.domain.com)",
    "  - pterodactyl_api_token: Your Pterodactyl API key from Account Settings > API Credentials",
    "  - steam_api_key: Your Steam Web API key from https://steamcommunity.com/dev/apikey",
    "",
  "Enable this feature by setting AUTO_UPDATE=1 in the Pterodactyl egg.",
    "",
    "Config location: /home/container/egg/configs/auto-restart.json"
  ],
  "check_interval": 300,
  "countdown_time": 300,
  "pterodactyl_url": "https://panel.domain.com",
  "pterodactyl_api_token": "",
  "steam_api_key": "",
  "commands": {
    "300": "say Attention: The server will update in 5 minutes. Please prepare to save your progress.",
    "60": "say Heads up: The server will update in 1 minute. Save your progress now.",
    "30": "say Warning: The server update is happening in 30 seconds. Get ready!",
    "10": "say Final notice: The server will update in 10 seconds. Please stand by.",
    "3": "say Final countdown: Update in 3 seconds. Hold tight!",
    "2": "say Final countdown: Update in 2 seconds. Almost there!",
    "1": "say Final countdown: Update in 1 second. Restarting now!"
  }
}
EOF
        
  # Merge old values if migration happened
        if [ -n "$old_values" ] && [ "$old_values" != "null" ]; then
            log_message "Merging previous settings..." "debug"
            local temp_file="${config_file}.tmp"
            jq --argjson old "$old_values" '. + $old | .version = "'"$CONFIG_VERSION"'"' "$config_file" > "$temp_file"
            mv "$temp_file" "$config_file"
        fi
    fi
}

create_webhook_config() {
    local config_file="$CONFIG_DIR/webhook.json"
    local old_values=""

  # Migrate if needed
    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "webhook")
    fi

    if [ ! -f "$config_file" ]; then
        log_message "Creating default webhook config..." "debug"
        cat > "$config_file" << 'EOF'
{
  "version": "1.0.0",
  "_description": [
    "Webhook Configuration",
    "",
    "Configure Discord webhook notifications for server events.",
    "",
    "Settings:",
    "  - url: Your Discord webhook URL (get from Server Settings > Integrations > Webhooks)",
    "  - notifications.update_detected: Send notification when CS2 update is found",
    "  - notifications.restart_initiated: Send notification when countdown starts",
    "  - notifications.restart_completed: Send notification when server is back online",
    "  - embed.color: Decimal color code for Discord embed (default: 16753920 = orange)",
    "  - embed.username: Bot username shown in Discord",
    "  - embed.avatar_url: Bot avatar image URL",
    "",
  "This feature is enabled automatically when webhook.json contains a non-empty 'url'.",
    "",
    "Config location: /home/container/egg/configs/webhook.json"
  ],
  "url": "",
  "notifications": {
    "update_detected": true,
    "restart_initiated": true,
    "restart_completed": false
  },
  "embed": {
    "color": 16753920,
    "username": "CS2 Auto Restart",
    "avatar_url": "https://kitsune-lab.com/storage/images/server.png"
  }
}
EOF
        
  # Merge old values if migration happened
        if [ -n "$old_values" ] && [ "$old_values" != "null" ]; then
            log_message "Merging previous settings..." "debug"
            local temp_file="${config_file}.tmp"
            jq --argjson old "$old_values" '. + $old | .version = "'"$CONFIG_VERSION"'"' "$config_file" > "$temp_file"
            mv "$temp_file" "$config_file"
        fi
    fi
}

create_console_filter_config() {
    local config_file="$CONFIG_DIR/console-filter.json"
    local old_values=""

  # Migrate if needed
    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "console-filter")
    fi

    if [ ! -f "$config_file" ]; then
        log_message "Creating default console-filter config..." "debug"
        cat > "$config_file" << 'EOF'
{
  "version": "1.0.0",
  "_description": [
    "Console Filter Configuration",
    "",
    "Filter unwanted console messages from CS2 server output.",
    "",
    "Settings:",
    "  - preview_mode: Show blocked messages in debug log (true/false)",
    "  - patterns: Array of filter patterns",
    "",
    "Pattern Matching:",
    "  - Prefix with @ for exact match: \"@Server is hibernating\"",
    "  - Without @ for contains match: \"edicts used\"",
    "",
    "Examples:",
    "  \"@exact text\" - Only blocks lines that match exactly",
    "  \"contains this\" - Blocks any line containing this text",
    "",
    "Note: STEAM_ACC token is automatically masked if set.",
    "",
    "Enable this feature by setting ENABLE_FILTER=1 in the Pterodactyl egg.",
    "",
    "Config location: /home/container/egg/configs/console-filter.json"
  ],
  "preview_mode": false,
  "patterns": [
    "Certificate expires"
  ]
}
EOF
        
  # Merge old values if migration happened
        if [ -n "$old_values" ] && [ "$old_values" != "null" ]; then
            log_message "Merging previous settings..." "debug"
            local temp_file="${config_file}.tmp"
            jq --argjson old "$old_values" '. + $old | .version = "'"$CONFIG_VERSION"'"' "$config_file" > "$temp_file"
            mv "$temp_file" "$config_file"
        fi
    fi
}

create_cleanup_config() {
    local config_file="$CONFIG_DIR/cleanup.json"
    local old_values=""

  # Migrate if needed
    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "cleanup")
    fi

    if [ ! -f "$config_file" ]; then
        log_message "Creating default cleanup config..." "debug"
        cat > "$config_file" << 'EOF'
{
  "version": "1.0.0",
  "_description": [
    "Cleanup Configuration",
    "",
    "Automatic cleanup of old logs, demos, and backup files.",
    "",
    "Settings:",
    "  - intervals.backup_rounds_hours: Delete backup_round*.txt files older than X hours",
    "  - intervals.demos_hours: Delete *.dem demo files older than X hours",
    "  - intervals.css_logs_hours: Delete CounterStrikeSharp logs older than X hours",
    "  - intervals.accelerator_dumps_hours: Delete Accelerator crash dumps older than X hours",
    "",
    "Paths:",
    "  - paths.game_directory: Base game directory (usually ./game/csgo)",
    "  - paths.accelerator_dumps: AcceleratorCS2 dumps directory",
    "",
    "Default intervals:",
    "  - Backup rounds: 24 hours (1 day)",
    "  - Demos: 168 hours (7 days)",
    "  - CSS logs: 72 hours (3 days)",
    "  - Accelerator dumps: 168 hours (7 days)",
    "",
  "Enable this feature by setting CLEANUP_ENABLED=1 in the Pterodactyl egg.",
    "",
    "Config location: /home/container/egg/configs/cleanup.json"
  ],
  "intervals": {
    "backup_rounds_hours": 24,
    "demos_hours": 168,
    "css_logs_hours": 72,
    "accelerator_dumps_hours": 168
  },
  "paths": {
    "game_directory": "./game/csgo",
    "accelerator_dumps": "./game/csgo/addons/AcceleratorCS2/dumps"
  }
}
EOF
        
  # Merge old values if migration happened
        if [ -n "$old_values" ] && [ "$old_values" != "null" ]; then
            log_message "Merging previous settings..." "debug"
            local temp_file="${config_file}.tmp"
            jq --argjson old "$old_values" '. + $old | .version = "'"$CONFIG_VERSION"'"' "$config_file" > "$temp_file"
            mv "$temp_file" "$config_file"
        fi
    fi
}

create_logging_config() {
    local config_file="$CONFIG_DIR/logging.json"
    local old_values=""

  # Migrate if needed
    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "logging")
    fi

    if [ ! -f "$config_file" ]; then
        log_message "Creating default logging config..." "debug"
        cat > "$config_file" << 'EOF'
{
  "version": "1.0.0",
  "_description": [
    "Logging Configuration",
    "",
    "Control console output formatting, colors, and file logging.",
    "",
    "Console Settings:",
    "  - logging.console_level: Minimum log level for console output",
    "    Available levels: DEBUG, INFO, WARNING, ERROR",
    "",
    "File Logging:",
    "  - logging.file_enabled: Enable daily rotating log files (true/false)",
    "  - logging.file_level: Minimum log level for file output",
    "  - logging.max_size_mb: Maximum total log directory size in MB",
    "  - logging.max_files: Maximum number of log files to keep",
    "  - logging.max_days: Maximum age of log files in days",
    "",
    "Log files stored in: /home/container/egg/logs/YYYY-MM-DD.log",
    "Rotation triggers when ANY limit is reached (size OR count OR age)",
    "",
    "Appearance:",
    "  - colors.enabled: Use colored console output (true/false)",
    "  - colors.use_emoji: Use emoji icons in logs (true/false)",
    "",
    "Note: This config is always loaded and does not require an environment variable.",
    "",
    "Config location: /home/container/egg/configs/logging.json"
  ],
  "logging": {
    "console_level": "INFO",
    "file_enabled": false,
    "file_level": "DEBUG",
    "max_size_mb": 100,
    "max_files": 30,
    "max_days": 7
  },
  "colors": {
    "enabled": true,
    "use_emoji": true
  }
}
EOF
        
  # Merge old values if migration happened
        if [ -n "$old_values" ] && [ "$old_values" != "null" ]; then
            log_message "Merging previous settings..." "debug"
            local temp_file="${config_file}.tmp"
            jq --argjson old "$old_values" '. + $old | .version = "'"$CONFIG_VERSION"'"' "$config_file" > "$temp_file"
            mv "$temp_file" "$config_file"
        fi
    fi
}

get_config_value() {
    local config_file="$1"
    local json_path="$2"
    local default_value="$3"
    local full_path="$CONFIG_DIR/$config_file"

    if [ ! -f "$full_path" ]; then
        echo "$default_value"
        return
    fi

  local value=$(jq -r "$json_path // \"$default_value\"" "$full_path" 2>/dev/null)

    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

load_configs() {
  # Load auto-restart config if enabled (AUTO_UPDATE preferred, fallback to UPDATE_AUTO_RESTART)
  if [ "${AUTO_UPDATE:-${UPDATE_AUTO_RESTART:-0}}" -eq 1 ]; then
        export RESTART_CHECK_INTERVAL=$(get_config_value "auto-restart.json" ".check_interval" "300")
        export RESTART_COUNTDOWN_TIME=$(get_config_value "auto-restart.json" ".countdown_time" "300")
        export UPDATE_COUNTDOWN_TIME="$RESTART_COUNTDOWN_TIME"
        export PTERODACTYL_URL=$(get_config_value "auto-restart.json" ".pterodactyl_url" "${PTERODACTYL_URL:-https://panel.domain.com}")
        export PTERODACTYL_API_TOKEN=$(get_config_value "auto-restart.json" ".pterodactyl_api_token" "${PTERODACTYL_API_TOKEN:-}")
        export STEAM_API_KEY=$(get_config_value "auto-restart.json" ".steam_api_key" "${STEAM_API_KEY:-}")

        # Load commands from config as JSON string
        local commands_json=$(jq -c '.commands' "$CONFIG_DIR/auto-restart.json" 2>/dev/null)
        if [ -n "$commands_json" ] && [ "$commands_json" != "null" ]; then
            export UPDATE_COMMANDS="$commands_json"
        fi
    fi

  # Load webhook config automatically if URL is present
  local _wh_url
  _wh_url=$(get_config_value "webhook.json" ".url" "")
  if [ -n "${_wh_url}" ]; then
    export DISCORD_WEBHOOK_URL="${_wh_url}"
    export WEBHOOK_NOTIFY_UPDATE=$(get_config_value "webhook.json" ".notifications.update_detected" "true")
    export WEBHOOK_NOTIFY_RESTART=$(get_config_value "webhook.json" ".notifications.restart_initiated" "true")
    export WEBHOOK_NOTIFY_COMPLETE=$(get_config_value "webhook.json" ".notifications.restart_completed" "false")
    export WEBHOOK_COLOR=$(get_config_value "webhook.json" ".embed.color" "16753920")
    export WEBHOOK_USERNAME=$(get_config_value "webhook.json" ".embed.username" "CS2 Auto Restart")
    export WEBHOOK_AVATAR=$(get_config_value "webhook.json" ".embed.avatar_url" "https://kitsune-lab.com/storage/images/server.png")
  fi

    # Load console filter config if enabled via environment variable
    if [ "${ENABLE_FILTER:-0}" -eq 1 ]; then
        export FILTER_PREVIEW_MODE=$(get_config_value "console-filter.json" ".preview_mode" "false")
    fi

  # Load cleanup config if enabled (supports CLEANUP_ENABLED, fallback ENABLE_CLEANUP)
  if [ "${CLEANUP_ENABLED:-${ENABLE_CLEANUP:-0}}" -eq 1 ]; then
        export CLEANUP_BACKUP_HOURS=$(get_config_value "cleanup.json" ".intervals.backup_rounds_hours" "24")
        export CLEANUP_DEMOS_HOURS=$(get_config_value "cleanup.json" ".intervals.demos_hours" "168")
        export CLEANUP_LOGS_HOURS=$(get_config_value "cleanup.json" ".intervals.css_logs_hours" "72")
        export CLEANUP_DUMPS_HOURS=$(get_config_value "cleanup.json" ".intervals.accelerator_dumps_hours" "168")
        export CLEANUP_GAME_DIR=$(get_config_value "cleanup.json" ".paths.game_directory" "./game/csgo")
        export CLEANUP_DUMPS_DIR=$(get_config_value "cleanup.json" ".paths.accelerator_dumps" "./game/csgo/addons/AcceleratorCS2/dumps")
    fi

    # Load logging config (always available, not feature-gated)
    export CONSOLE_LOG_LEVEL=$(get_config_value "logging.json" ".logging.console_level" "INFO")
    export LOG_FILE_ENABLED=$(get_config_value "logging.json" ".logging.file_enabled" "false")
    export LOG_FILE_LEVEL=$(get_config_value "logging.json" ".logging.file_level" "DEBUG")
    export LOG_MAX_SIZE_MB=$(get_config_value "logging.json" ".logging.max_size_mb" "100")
    export LOG_MAX_FILES=$(get_config_value "logging.json" ".logging.max_files" "30")
    export LOG_MAX_DAYS=$(get_config_value "logging.json" ".logging.max_days" "7")
    export LOG_COLORS_ENABLED=$(get_config_value "logging.json" ".colors.enabled" "true")
    export LOG_USE_EMOJI=$(get_config_value "logging.json" ".colors.use_emoji" "true")
}