#!/bin/bash

source /utils/logging.sh
source /utils/updater_common.sh

update_matchzy() {
    local REPO="shobhit-pathak/MatchZy"
    local CSGO_DIR="/home/container/game/csgo"
    local PLUGIN_DLL="$CSGO_DIR/addons/counterstrikesharp/plugins/MatchZy/MatchZy.dll"
    local temp_dir="$TEMP_DIR/matchzy"
    local archive="$TEMP_DIR/matchzy.zip"

    mkdir -p "$TEMP_DIR" "$CSGO_DIR"
    rm -rf "$temp_dir" "$archive"
    mkdir -p "$temp_dir"

    local release_info

    # Stable releases only.
    # This deliberately selects the plugin-only ZIP and excludes
    # MatchZy-with-cssharp-linux.zip.
    release_info=$(
        PRERELEASE=0 get_github_release \
            "$REPO" \
            '^MatchZy-[0-9]+(\.[0-9]+)*\.zip$'
    )

    if [ -z "$release_info" ] ||
       ! echo "$release_info" | jq -e . >/dev/null 2>&1; then
        log_message "Failed to get MatchZy release information" "error"
        return 1
    fi

    local new_version
    local asset_url
    local current_version

    new_version=$(echo "$release_info" | jq -r '.version // empty')
    asset_url=$(echo "$release_info" | jq -r '.asset_url // empty')
    current_version=$(get_current_version "MATCHZY")

    # Reinstall if versions.txt exists but the actual DLL was deleted.
    if [ ! -f "$PLUGIN_DLL" ]; then
        current_version=""
    fi

    if [ -z "$new_version" ] || [ -z "$asset_url" ]; then
        log_message "No suitable MatchZy release asset was found" "error"
        return 1
    fi

    if ! check_version \
        "MatchZy" \
        "${current_version:-none}" \
        "$new_version"; then
        return 0
    fi

    if ! handle_download_and_extract \
        "$asset_url" \
        "$archive" \
        "$temp_dir" \
        "zip"; then
        return 1
    fi

    # Handle the common release layouts:
    #
    # addons/...
    # cfg/...
    #
    # game/csgo/addons/...
    #
    # csgo/addons/...
    local payload="$temp_dir"

    if [ -d "$temp_dir/game/csgo/addons" ]; then
        payload="$temp_dir/game/csgo"
    elif [ -d "$temp_dir/csgo/addons" ]; then
        payload="$temp_dir/csgo"
    fi

    if [ ! -d "$payload/addons" ]; then
        log_message \
            "MatchZy archive does not contain an addons directory" \
            "error"
        return 1
    fi

    mkdir -p "$CSGO_DIR/addons"

    # Update plugin binaries and plugin resources.
    rsync -a \
        "$payload/addons/" \
        "$CSGO_DIR/addons/"

    # Install new MatchZy config files without overwriting existing
    # server-specific MatchZy configuration.
    if [ -d "$payload/cfg" ]; then
        mkdir -p "$CSGO_DIR/cfg"

        rsync -a --ignore-existing \
            "$payload/cfg/" \
            "$CSGO_DIR/cfg/"
    fi

    update_version_file "MATCHZY" "$new_version"

    log_message \
        "MatchZy updated to $new_version" \
        "success"
}

main() {
    mkdir -p "$TEMP_DIR"
    update_matchzy
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
