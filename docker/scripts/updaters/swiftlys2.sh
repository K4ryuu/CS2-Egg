#!/bin/bash
# SwiftlyS2 Auto-Update Script
# Downloads and installs SwiftlyS2 from GitHub releases

source /utils/logging.sh
source /utils/updater_common.sh

# Update Swiftly
update_swiftly() {
    local OUTPUT_DIR="./game/csgo/addons"
    local REPO="swiftly-solution/swiftlys2"
    local temp_dir="$TEMP_DIR/swiftly"

    mkdir -p "$OUTPUT_DIR" "$temp_dir"
    rm -rf "$temp_dir"/*

    local release_info
    release_info=$(fetch_release "SwiftlyS2" "$REPO" "linux.*with-runtimes\\.zip") || return 1

    local new_version=$(echo "$release_info" | jq -r '.version // empty')
    local asset_url=$(echo "$release_info" | jq -r '.asset_url // empty')

    needs_update "SwiftlyS2" "Swiftly" "$new_version" || return 0

    if [ -z "$asset_url" ]; then
        log_message "No suitable asset found for $REPO" "error"
        return 0
    fi

    if handle_download_and_extract "$asset_url" "$temp_dir/download.zip" "$temp_dir" "zip"; then
        # Find swiftlys2 directory (handles versioned top-level folders)
        local swiftly_dir=$(find "$temp_dir" -type d -name "swiftlys2" -path "*/addons/swiftlys2" | head -n1)

        if [ -n "$swiftly_dir" ] && [ -d "$swiftly_dir" ]; then
            local target_dir="$OUTPUT_DIR/swiftlys2"

            if [ -d "$target_dir" ]; then
                # Update: only overwrite bin/ and gamedata/ (preserve user configs and plugins)
                if cp -rf "$swiftly_dir/bin" "$target_dir/" && cp -rf "$swiftly_dir/gamedata" "$target_dir/"; then
                    update_version_file "Swiftly" "$new_version"
                    log_message "SwiftlyS2 updated to $new_version (bin + gamedata)" "success"
                    return 0
                fi
            else
                # Fresh install: copy everything
                if cp -rf "$swiftly_dir" "$OUTPUT_DIR/"; then
                    update_version_file "Swiftly" "$new_version"
                    log_message "SwiftlyS2 installed $new_version" "success"
                    return 0
                fi
            fi

            # version file NOT bumped, so the updater retries next boot
            log_message "SwiftlyS2 copy failed - keeping previous version" "error"
            return 1
        else
            log_message "SwiftlyS2 directory not found in archive" "error"
            return 1
        fi
    fi

    return 1
}

# only when run standalone: update.sh sources this and calls the function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_updater update_swiftly
fi
