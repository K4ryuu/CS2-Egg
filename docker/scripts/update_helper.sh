#!/bin/bash

source /utils/logging.sh

# Legacy migration - move old files to new egg directory structure
migrate_legacy_files() {
    local egg_dir="/home/container/egg"
    local old_log="/home/container/egg.log"
    local old_version="/home/container/game/versions.txt"
    local old_mute_cfg="/home/container/game/mute_messages.cfg"

    # Only run if the egg directory doesn't exist yet
    if [ -d "$egg_dir" ]; then
        return 0
    fi

    log_message "Detected first run with new structure - checking for legacy files..." "info"

    local found_legacy=false

    # Check for old egg.log file
    if [ -f "$old_log" ]; then
        log_message "Found legacy egg.log - migrating to new log system..." "info"

        # Create logs directory
        mkdir -p "${egg_dir}/logs"

        # Move old log with timestamp
        local timestamp=$(date +%Y-%m-%d)
        mv "$old_log" "${egg_dir}/logs/${timestamp}.log"

        log_message "Migrated egg.log → egg/logs/${timestamp}.log" "success"
        found_legacy=true
    fi

    # Check for old version file
    if [ -f "$old_version" ]; then
        log_message "Found legacy versions.txt - migrating..." "info"

        # Create egg directory if needed
        mkdir -p "$egg_dir"

        # Move to new location
        mv "$old_version" "${egg_dir}/versions.txt"

        log_message "Migrated game/versions.txt → egg/versions.txt" "success"
        found_legacy=true
    fi

    # Check for old mute_messages.cfg
    if [ -f "$old_mute_cfg" ]; then
        log_message "Found legacy mute_messages.cfg - migrating..." "info"

        # Create configs directory
        mkdir -p "${egg_dir}/configs"

        # Parse old format and convert to new console-filter.json
        local patterns=()

        # Read patterns from old config (skip comments and empty lines)
        while IFS= read -r line; do
            # Skip comments and empty lines
            local trimmed=$(echo "$line" | xargs)
            if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "$trimmed" ]]; then
                # Add to patterns array
                patterns+=("$trimmed")
            fi
        done < "$old_mute_cfg"

        # Create new console-filter.json with migrated patterns
        local json_patterns=""
        for pattern in "${patterns[@]}"; do
            if [ -z "$json_patterns" ]; then
                json_patterns="\"$pattern\""
            else
                json_patterns="${json_patterns}, \"$pattern\""
            fi
        done

        # If no patterns found, use empty array
        if [ -z "$json_patterns" ]; then
            json_patterns=""
        fi

        # Generate the new config file with patterns inline
        cat > "${egg_dir}/configs/console-filter.json" <<CONFIGEOF
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
    "Config location: /home/container/egg/configs/console-filter.json",
    "",
    "NOTE: This config was automatically migrated from legacy mute_messages.cfg"
  ],
  "preview_mode": false,
  "patterns": [${json_patterns}]
}
CONFIGEOF

        # Backup old file instead of deleting
        mv "$old_mute_cfg" "${old_mute_cfg}.backup"

        log_message "Migrated mute_messages.cfg → egg/configs/console-filter.json" "success"
        log_message "Old file backed up as mute_messages.cfg.backup" "debug"
        found_legacy=true
    fi

    if [ "$found_legacy" = true ]; then
        log_message "Legacy file migration completed!" "success"
        log_message "You can safely delete the backup files if everything works correctly" "info"
    else
        log_message "No legacy files found - clean installation" "debug"
    fi
}

# Run migration check
migrate_legacy_files
