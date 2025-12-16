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
    release_info=$(get_github_release "$REPO" "linux.*with-runtimes\\.zip")

    # Validate JSON response
    if [ -z "$release_info" ] || ! echo "$release_info" | jq -e . >/dev/null 2>&1; then
        log_message "Failed to get release info for $REPO" "error"
        return 1
    fi

    local new_version=$(echo "$release_info" | jq -r '.version // empty')
    local asset_url=$(echo "$release_info" | jq -r '.asset_url // empty')
    local current_version=$(get_current_version "Swiftly")

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
            local target_dir="$OUTPUT_DIR/swiftlys2"

            if [ -d "$target_dir" ]; then
                # Update: only overwrite bin/ and gamedata/ (preserve user configs and plugins)
                cp -rf "$swiftly_dir/bin" "$target_dir/" && \
                cp -rf "$swiftly_dir/gamedata" "$target_dir/" && \
                log_message "SwiftlyS2 updated to $new_version (bin + gamedata)" "success"
            else
                # Fresh install: copy everything
                cp -rn "$swiftly_dir" "$OUTPUT_DIR/" && \
                log_message "SwiftlyS2 installed $new_version" "success"
            fi

            update_version_file "Swiftly" "$new_version"
            return 0
        else
            log_message "SwiftlyS2 directory not found in archive" "error"
            return 1
        fi
    fi

    return 1
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
