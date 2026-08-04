#!/bin/bash
# CounterStrikeSharp Auto-Update Script
# Downloads and installs CounterStrikeSharp from GitHub releases

source /utils/logging.sh
source /utils/updater_common.sh

update_counterstrikesharp() {
    local OUTPUT_DIR="./game/csgo/addons"
    local REPO="roflmuffin/CounterStrikeSharp"
    local temp_dir="$TEMP_DIR/css"

    mkdir -p "$OUTPUT_DIR" "$temp_dir"
    rm -rf "$temp_dir"/*

    local release_info
    release_info=$(fetch_release "CSS" "$REPO" "-with-runtime-linux-.*\\.zip$") || return 1

    local new_version=$(echo "$release_info" | jq -r '.version // empty')
    local asset_url=$(echo "$release_info" | jq -r '.asset_url // empty')

    needs_update "CSS" "CSS" "$new_version" || return 0

    if [ -z "$asset_url" ]; then
        log_message "No suitable asset found for $REPO" "error"
        return 0
    fi

    if handle_download_and_extract "$asset_url" "$temp_dir/download.zip" "$temp_dir" "zip"; then
        if cp -r "$temp_dir/addons/." "$OUTPUT_DIR"; then
            update_version_file "CSS" "$new_version"
            log_message "CounterStrikeSharp updated to $new_version" "success"
            return 0
        fi
        # version file NOT bumped, so the updater retries next boot
        log_message "CounterStrikeSharp copy failed - keeping previous version" "error"
    fi

    return 1
}

# only when run standalone: update.sh sources this and calls the function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_updater update_counterstrikesharp
fi
