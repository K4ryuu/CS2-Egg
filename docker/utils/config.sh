#!/bin/bash

source /utils/logging.sh

# Current config version - bump this when changing fields
CONFIG_VERSION="1.1.0"

# Use organized egg directory structure
CONFIG_DIR="${EGG_CONFIGS_DIR:-/home/container/egg/configs}"

# Check if any config needs migration
check_config_versions() {
    local needs_migration=false
    local old_version=""

    # Check all config files
    for config_file in "$CONFIG_DIR/console-filter.json" "$CONFIG_DIR/cleanup.json" "$CONFIG_DIR/logging.json"; do
        if [ -f "$config_file" ]; then
            local current_version=$(jq -r '.version // "0.0.0"' "$config_file" 2>/dev/null)
            if [ "$current_version" != "$CONFIG_VERSION" ]; then
                needs_migration=true
                old_version="$current_version"
                break
            fi
        fi
    done

    # Log once if migration is needed
    if [ "$needs_migration" = true ]; then
        log_message "Migrating configs from v$old_version to v$CONFIG_VERSION" "info"
    fi
}

# Migrate old config to new version (no logging, just migration)
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

    # Extract old values
    local old_values=$(jq -r 'del(._description) | del(.version)' "$config_file" 2>/dev/null)

    # Remove old config
    rm "$config_file"

    # Return the old values so we can merge them
    echo "$old_values"
}

# Apply smart merge to config file (centralized jq logic)
apply_smart_merge() {
    local config_file="$1"
    local old_values="$2"

    if [ -z "$old_values" ] || [ "$old_values" = "null" ]; then
        return 0
    fi

    log_message "Merging previous settings..." "debug"
    local temp_file="${config_file}.tmp"

    jq --argjson old "$old_values" '
        def smart_merge($old):
            . as $new |
            if ($new | type) == "object" then
                $new | to_entries | map(
                    .key as $k |
                    if ($new[$k] | type) == "object" then
                        {key: $k, value: ($new[$k] | smart_merge($old[$k] // {}))}
                    else
                        {key: $k, value: ($old[$k] // $new[$k])}
                    end
                ) | from_entries
            else
                $old // $new
            end;
        smart_merge($old) | .version = "'"$CONFIG_VERSION"'"
    ' "$config_file" > "$temp_file"

    mv "$temp_file" "$config_file"
}

init_configs() {
  # Initialize egg directories (from logging.sh)
    init_egg_directories

    mkdir -p "$CONFIG_DIR"

    # Check if migration is needed (logs once if yes)
    check_config_versions

    create_console_filter_config
    create_cleanup_config
    create_logging_config
}

create_console_filter_config() {
    local config_file="$CONFIG_DIR/console-filter.json"
    local old_values=""

  # Migrate if needed
    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "console-filter")
    fi

    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
{
  "version": "$CONFIG_VERSION",
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
        apply_smart_merge "$config_file" "$old_values"
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
        cat > "$config_file" << EOF
{
  "version": "$CONFIG_VERSION",
  "_description": [
    "Cleanup Configuration — rule-based",
    "",
    "Every entry in 'rules' is an independent cleanup target. You can edit,",
    "disable, add, or remove rules without touching any code.",
    "",
    "Rule fields:",
    "  - name: Stat category shown in log output (e.g. 'demos', 'backup_rounds')",
    "  - description: Free-text comment (ignored by the engine)",
    "  - directories: Array of paths to search (relative to /home/container or absolute)",
    "  - patterns: Array of filename globs (e.g. '*.dem', 'core.[0-9]*')",
    "  - hours: File must be older than this many hours (0 = delete on every run)",
    "  - recursive: true = walk subdirectories, false = only the directory root",
    "  - enabled: false disables the rule without deleting it",
    "",
    "Enable cleanup by setting CLEANUP_ENABLED=1 in the Pterodactyl egg.",
    "",
    "Config location: /home/container/egg/configs/cleanup.json"
  ],
  "rules": [
    {
      "name": "backup_rounds",
      "description": "CS2 match backup round snapshots",
      "directories": ["./game/csgo"],
      "patterns": ["backup_round*.txt"],
      "hours": 24,
      "recursive": true,
      "enabled": true
    },
    {
      "name": "demos",
      "description": "SourceTV demo recordings",
      "directories": ["./game/csgo"],
      "patterns": ["*.dem"],
      "hours": 168,
      "recursive": true,
      "enabled": true
    },
    {
      "name": "css_logs",
      "description": "CounterStrikeSharp log files",
      "directories": ["./game/csgo/addons/counterstrikesharp/logs"],
      "patterns": ["*.txt"],
      "hours": 72,
      "recursive": true,
      "enabled": true
    },
    {
      "name": "swiftly_logs",
      "description": "SwiftlyS2 log files",
      "directories": ["./game/csgo/addons/swiftlys2/logs"],
      "patterns": ["*.log"],
      "hours": 72,
      "recursive": true,
      "enabled": true
    },
    {
      "name": "accelerator_dumps",
      "description": "AcceleratorCS2 crash dumps and reports",
      "directories": ["./game/csgo/addons/AcceleratorCS2/dumps"],
      "patterns": ["*.dmp", "*.dmp.txt"],
      "hours": 168,
      "recursive": true,
      "enabled": true
    },
    {
      "name": "core_dumps",
      "description": "Linux core dumps (delete on every run)",
      "directories": ["./game/bin/linuxsteamrt64", "/home/container"],
      "patterns": ["core", "core.[0-9]*"],
      "hours": 0,
      "recursive": false,
      "enabled": true
    }
  ]
}
EOF

        # Merge old values if migration happened
        apply_smart_merge "$config_file" "$old_values"
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
        cat > "$config_file" << EOF
{
  "version": "$CONFIG_VERSION",
  "_description": [
    "Logging Configuration",
    "",
    "Control console output level and file logging.",
    "",
    "Console Settings:",
    "  - logging.console_level: Minimum log level for console output",
    "    Available levels: DEBUG, INFO, WARNING, ERROR",
    "",
    "File Logging:",
    "  - logging.file_enabled: Enable daily rotating log files (true/false)",
    "  - logging.max_size_mb: Maximum total log directory size in MB",
    "  - logging.max_files: Maximum number of log files to keep",
    "  - logging.max_days: Maximum age of log files in days",
    "",
    "Log files stored in: /home/container/egg/logs/YYYY-MM-DD.log",
    "Rotation triggers when ANY limit is reached (size OR count OR age)",
    "",
    "Note: This config is always loaded and does not require an environment variable.",
    "",
    "Config location: /home/container/egg/configs/logging.json"
  ],
  "logging": {
    "console_level": "INFO",
    "file_enabled": false,
    "max_size_mb": 100,
    "max_files": 30,
    "max_days": 7
  }
}
EOF

        # Merge old values if migration happened
        apply_smart_merge "$config_file" "$old_values"
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
    # Load console filter config if enabled via environment variable
    if [ "${ENABLE_FILTER:-0}" -eq 1 ]; then
        export FILTER_PREVIEW_MODE=$(get_config_value "console-filter.json" ".preview_mode" "false")
    fi

    # Load logging config (always available, not feature-gated)
    export CONSOLE_LOG_LEVEL=$(get_config_value "logging.json" ".logging.console_level" "INFO")
    export LOG_FILE_ENABLED=$(get_config_value "logging.json" ".logging.file_enabled" "false")
    export LOG_MAX_SIZE_MB=$(get_config_value "logging.json" ".logging.max_size_mb" "100")
    export LOG_MAX_FILES=$(get_config_value "logging.json" ".logging.max_files" "30")
    export LOG_MAX_DAYS=$(get_config_value "logging.json" ".logging.max_days" "7")
}