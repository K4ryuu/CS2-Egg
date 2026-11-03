#!/bin/bash
# MetaMod Auto-Update Script
# Downloads from GitHub releases only

source /utils/logging.sh
source /utils/updater_common.sh

update_metamod() {
    local OUTPUT_DIR="./game/csgo/addons"

    if [ ! -d "$OUTPUT_DIR/metamod" ]; then
        log_message "Installing Metamod..." "info"
    fi

    # MetaMod CS2 builds are prerelease on GitHub - always use prerelease channel
    local release
    release=$(PRERELEASE=1 fetch_release "Metamod" "alliedmodders/metamod-source" \
        "^mmsource-2\.[0-9]+\.[0-9]+-git[0-9]+-linux\.tar\.gz$" "^2\.") || return 1

    local asset_url asset_name new_version
    asset_url=$(echo "$release" | jq -r '.asset_url')
    asset_name=$(echo "$release" | jq -r '.asset_name')

    if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
        log_message "No Linux asset found in Metamod release" "error"
        return 1
    fi

    # version lives in the asset name, not the tag (mmsource-2.0.0-git1391-linux.tar.gz)
    new_version=$(echo "$asset_name" | grep -o 'git[0-9]\+')

    needs_update "Metamod" "Metamod" "$new_version" || return 0

    if handle_download_and_extract "$asset_url" "$TEMP_DIR/metamod.tar.gz" "$TEMP_DIR/metamod" "tar.gz"; then
        local cs2_library="$TEMP_DIR/metamod/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so"
        if [ ! -s "$cs2_library" ]; then
            log_message "MetaMod archive is missing the CS2 linuxsteamrt64 library" "error"
            return 1
        fi

        if cp -rf "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/"; then
            if update_version_file "Metamod" "$new_version"; then
                log_message "Metamod updated to $new_version" "success"
                return 0
            fi
            log_message "Metamod version stamp failed - update will be retried" "error"
            return 1
        fi
        # version file NOT bumped, so the updater retries next boot
        log_message "Metamod copy failed - keeping previous version" "error"
    fi

    return 1
}

# only when run standalone: update.sh sources this and calls the function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_updater update_metamod
fi
