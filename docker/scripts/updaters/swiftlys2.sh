#!/bin/bash
# SwiftlyS2 Auto-Update Script
# Downloads and installs SwiftlyS2 from GitHub releases

source /utils/logging.sh
source /utils/version.sh
source /utils/updater_common.sh

# Update Swiftly
update_swiftly() {
    local OUTPUT_DIR="./game/csgo/addons"
    local TEMP_DIR="./temps"
    local REPO="swiftly-solution/swiftlys2"
    local temp_dir="$TEMP_DIR/swiftly"

    mkdir -p "$OUTPUT_DIR" "$temp_dir"
    rm -rf "$temp_dir"/*

    local api_response=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
    if [ -z "$api_response" ]; then
        log_message "Failed to get release info for $REPO" "error"
        return 1
    fi

    local new_version=$(echo "$api_response" | jq -r '.tag_name // empty')
    local current_version=$(get_current_version "Swiftly")
    local asset_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | test("linux.*with-runtimes\\.zip")) | .browser_download_url' | head -n1)

    if [ -z "$new_version" ]; then
        log_message "Failed to get version for $REPO" "error"
        return 0
    fi

    # Check if update needed
    if [ "$current_version" = "$new_version" ]; then
        log_message "SwiftlyS2 is up-to-date ($current_version)" "info"
        return 0
    fi

    if [ -z "$asset_url" ]; then
        log_message "No suitable asset found for $REPO" "error"
        return 0
    fi

    log_message "Update available for SwiftlyS2: $new_version (current: ${current_version:-none})" "info"

    if handle_download_and_extract "$asset_url" "$temp_dir/download.zip" "$temp_dir" "zip"; then
        # Find swiftlys2 directory (handles versioned top-level folders)
        local swiftly_dir=$(find "$temp_dir" -type d -name "swiftlys2" -path "*/addons/swiftlys2" | head -n1)

        if [ -n "$swiftly_dir" ] && [ -d "$swiftly_dir" ]; then
            cp -rn "$swiftly_dir" "$OUTPUT_DIR/" && \
            update_version_file "Swiftly" "$new_version" && \
            log_message "SwiftlyS2 updated to $new_version" "success"
            return 0
        else
            log_message "SwiftlyS2 directory not found in archive" "error"
            return 1
        fi
    fi

    return 1
}

# Configure SwiftlyS2 in gameinfo.gi
configure_swiftly() {
    local GAMEINFO_FILE="/home/container/game/csgo/gameinfo.gi"
    local GAMEINFO_ENTRY="\t\t\tGame\tcsgo/addons/swiftlys2"
    local OLD_VDF="/home/container/game/csgo/addons/metamod/swiftlys2.vdf"

    if [ -f "${GAMEINFO_FILE}" ]; then
        if ! grep -q "csgo/addons/swiftlys2" "$GAMEINFO_FILE"; then
            awk -v new_entry="$GAMEINFO_ENTRY" '
                BEGIN { found=0; }
                {
                    if (found) {
                        print new_entry;
                        found=0;
                    }
                    print;
                }
                /Game_LowViolence/ { found=1; }
            ' "$GAMEINFO_FILE" > "$GAMEINFO_FILE.tmp" && mv "$GAMEINFO_FILE.tmp" "$GAMEINFO_FILE"
            log_message "SwiftlyS2 configured in gameinfo.gi" "debug"
        fi

        # Remove old swiftlys2.vdf from metamod directory to avoid conflicts
        if [ -f "$OLD_VDF" ]; then
            rm -f "$OLD_VDF"
            log_message "Removed old swiftlys2.vdf from metamod" "debug"
        fi
    fi
}

# Main function
main() {
    mkdir -p "$TEMP_DIR"
    update_swiftly
    return $?
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
