#!/bin/bash
# CounterStrikeSharp Auto-Update Script
# Downloads and installs CounterStrikeSharp from GitHub releases

source /utils/logging.sh
source /utils/version.sh
source /utils/updater_common.sh

# Configuration
OUTPUT_DIR="./game/csgo/addons"
TEMP_DIR="./temps"
REPO="roflmuffin/CounterStrikeSharp"

update_counterstrikesharp() {
    local temp_dir="$TEMP_DIR/css"

    mkdir -p "$OUTPUT_DIR" "$temp_dir"
    rm -rf "$temp_dir"/*

    local api_response=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
    if [ -z "$api_response" ]; then
        log_message "Failed to get release info for $REPO" "error"
        return 1
    fi

    local new_version=$(echo "$api_response" | jq -r '.tag_name // empty')
    local current_version=$(get_current_version "CSS")
    local asset_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | test("-with-runtime-linux-.*\\.zip$")) | .browser_download_url' | head -n1)

    if [ -z "$new_version" ]; then
        log_message "Failed to get version for $REPO" "debug"
        return 0
    fi

    # Check if update needed
    if [ "$current_version" = "$new_version" ]; then
        log_message "CSS is up-to-date ($current_version)" "debug"
        return 0
    fi

    if [ -z "$asset_url" ]; then
        log_message "No suitable asset found for $REPO" "debug"
        return 0
    fi

    log_message "Update available for CSS: $new_version (current: ${current_version:-none})" "info"

    if handle_download_and_extract "$asset_url" "$temp_dir/download.zip" "$temp_dir" "zip"; then
        cp -r "$temp_dir/addons/." "$OUTPUT_DIR" && \
        update_version_file "CSS" "$new_version" && \
        log_message "CounterStrikeSharp updated to $new_version" "success"
        return 0
    fi

    return 1
}

# Main function
main() {
    mkdir -p "$TEMP_DIR"
    update_counterstrikesharp
    return $?
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
