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
    release=$(PRERELEASE=1 get_github_release "alliedmodders/metamod-source" "linux\.tar\.gz$")
    if [ -z "$release" ]; then
        log_message "Failed to fetch Metamod release info from GitHub" "error"
        return 1
    fi

    local asset_url asset_name new_version
    asset_url=$(echo "$release" | jq -r '.asset_url')
    asset_name=$(echo "$release" | jq -r '.asset_name')

    if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
        log_message "No Linux asset found in Metamod release" "error"
        return 1
    fi

    # Extract git build number from asset filename (e.g. mmsource-2.0.0-git1391-linux.tar.gz)
    new_version=$(echo "$asset_name" | grep -o 'git[0-9]\+')
    if [ -z "$new_version" ]; then
        log_message "Failed to parse Metamod version from asset: $asset_name" "error"
        return 1
    fi

    local current_version
    current_version=$(get_current_version "Metamod")

    if [ -n "$current_version" ]; then
        semver_compare "$new_version" "$current_version"
        case $? in
            0)
                log_message "Metamod is up-to-date ($current_version)" "info"
                return 0
                ;;
            2)
                log_message "Metamod is at a newer version ($current_version) than latest ($new_version). Skipping downgrade." "info"
                return 0
                ;;
        esac
    fi

    log_message "Update available for Metamod: $new_version (current: ${current_version:-none})" "info"

    if handle_download_and_extract "$asset_url" "$TEMP_DIR/metamod.tar.gz" "$TEMP_DIR/metamod" "tar.gz"; then
        cp -rf "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/" && \
        update_version_file "Metamod" "$new_version" && \
        log_message "Metamod updated to $new_version" "success"
        return 0
    fi

    return 1
}

main() {
    mkdir -p "$TEMP_DIR"
    update_metamod
    return $?
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
