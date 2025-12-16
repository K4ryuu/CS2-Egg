#!/bin/bash
# MetaMod Auto-Update Script
# Downloads and installs MetaMod from AlliedMods

source /utils/logging.sh
source /utils/updater_common.sh

update_metamod() {
    local OUTPUT_DIR="./game/csgo/addons"

    if [ ! -d "$OUTPUT_DIR/metamod" ]; then
        log_message "Installing Metamod..." "info"
    fi

    local metamod_version=$(curl -sL https://mms.alliedmods.net/mmsdrop/2.0/ | grep -oP 'href="\K(mmsource-[^"]*-linux\.tar\.gz)' | tail -1)
    if [ -z "$metamod_version" ]; then
        log_message "Failed to fetch the Metamod version" "error"
        return 1
    fi

    local full_url="https://mms.alliedmods.net/mmsdrop/2.0/$metamod_version"
    local new_version=$(echo "$metamod_version" | grep -oP 'git\d+')
    local current_version=$(get_current_version "Metamod")

    # Check if update needed
    if [ "$current_version" = "$new_version" ]; then
        log_message "Metamod is up-to-date ($current_version)" "info"
        return 0
    fi

    log_message "Update available for Metamod: $new_version (current: ${current_version:-none})" "info"

    if handle_download_and_extract "$full_url" "$TEMP_DIR/metamod.tar.gz" "$TEMP_DIR/metamod" "tar.gz"; then
        cp -rf "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/" && \
        update_version_file "Metamod" "$new_version" && \
        log_message "Metamod updated to $new_version" "success"
        return 0
    fi

    return 1
}

# Main function
main() {
    mkdir -p "$TEMP_DIR"
    update_metamod
    return $?
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
