#!/bin/bash
source /utils/logging.sh
source /utils/version.sh

cleanup_and_update() {
    # Directories
    GAME_DIRECTORY="./game/csgo"
    OUTPUT_DIR="./game/csgo/addons"
    TEMP_DIR="./temps"
    LOG_FILE="./game/startup_log.txt"
    VERSION_FILE="./game/versions.txt"

    # Delete previous log file if exists
    rm -f "$LOG_FILE"

    if [ "$CLEANUP_ENABLED" = "1" ]; then
        cleanup
    fi

    # Ensure versions.txt exists
    if [ ! -f "$VERSION_FILE" ]; then
        touch "$VERSION_FILE"
    fi

    if [ "$METAMOD_AUTOUPDATE" = "1" ] || ([ ! -d "$OUTPUT_DIR/metamod" ] && [ "$CSS_AUTOUPDATE" = "1" ]); then
        update_metamod
    fi

    if [ "$CSS_AUTOUPDATE" = "1" ]; then
        log_message "Updating CounterStrikeSharp..." "running"
        update_addon "roflmuffin/CounterStrikeSharp" "$OUTPUT_DIR" "css" "CSS"
    fi

    # Clean up
    log_message "Cleaning up temporary files..." "running"
    rm -rf "$TEMP_DIR"
    log_message "Cleanup completed." "success"
}

update_addon() {
    local repo="$1"
    local output_path="$2"
    local temp_subdir="$3"
    local addon_name="$4"
    local current_version
    local new_version

    mkdir -p "$output_path"
    mkdir -p "$TEMP_DIR/$temp_subdir"
    rm -rf "$TEMP_DIR/$temp_subdir"/*

    API_URL="https://api.github.com/repos/$repo/releases/latest"
    response=$(curl -s $API_URL)

    asset_url=$(echo $response | grep -oP '"browser_download_url": "\K[^"]+' | grep 'counterstrikesharp-with-runtime-build-.*-linux-.*\.zip')
    new_version=$(echo $response | grep -oP '"tag_name": "\K[^"]+')
    current_version=$(get_current_version "$addon_name")

    if [ "$current_version" != "$new_version" ]; then
        log_message "New version of $addon_name available: $new_version (current: $current_version)" "running"

        if [ -z "$asset_url" ]; then
            log_message "Failed to find the asset URL for $repo. Skipping update." "error"
            return 1
        fi

        file_name=$(basename $asset_url)
        log_message "Downloading $file_name..." "running"

        curl -fsSL -m 300 -o "$TEMP_DIR/$temp_subdir/$file_name" "$asset_url"
        if [ $? -ne 0 ]; then
            log_message "Failed to download $file_name from $asset_url" "error"
            return 1
        fi

        if [ ! -s "$TEMP_DIR/$temp_subdir/$file_name" ]; then
            log_message "Downloaded file $file_name is empty or not found." "error"
            return 1
        fi

        log_message "Extracting $file_name..." "running"
        unzip -qq -o "$TEMP_DIR/$temp_subdir/$file_name" -d "$TEMP_DIR/$temp_subdir"

        if [ $? -ne 0 ]; then
            log_message "Failed to extract $file_name. Skipping update." "error"
            return 1
        fi

        log_message "Copying files to $output_path..." "running"
        cp -r "$TEMP_DIR/$temp_subdir/addons/." "$output_path"

        update_version_file "$addon_name" "$new_version"
        log_message "Update of $repo completed successfully." "success"
    else
        log_message "No new version of $addon_name available. Skipping update." "success"
    fi
}

update_metamod() {
    if [ "$METAMOD_AUTOUPDATE" = "1" ] || ([ ! -d "$OUTPUT_DIR/metamod" ] && [ "$CSS_AUTOUPDATE" = "1" ]); then
        if [ ! -d "$OUTPUT_DIR/metamod" ]; then
            log_message "Metamod not installed. Installing Metamod..." "running"
        else
            log_message "Updating Metamod..." "running"
        fi

        metamod_version=$(curl -sL https://mms.alliedmods.net/mmsdrop/2.0/ | grep -oP 'href="\K(mmsource-[^"]*-linux\.tar\.gz)' | tail -1)

        if [ -z "$metamod_version" ]; then
            log_message "Failed to fetch the Metamod version." "error"
            exit 1
        fi

        full_url="https://mms.alliedmods.net/mmsdrop/2.0/$metamod_version"
        new_version=$(echo $metamod_version | grep -oP 'git\d+')
        current_version=$(get_current_version "Metamod")

        if [ "$current_version" != "$new_version" ]; then
            log_message "New version of Metamod available: $new_version (current: $current_version)" "running"
            log_message "Downloading Metamod from URL: $full_url" "running"

            http_code=$(curl -s -L -w "%{http_code}" -o "$TEMP_DIR/metamod.tar.gz" "$full_url")
            if [ "$http_code" -ne 200 ]; then
                log_message "Failed to download Metamod from $full_url. HTTP status code: $http_code" "error"
                return 1
            fi

            if [ ! -s "$TEMP_DIR/metamod.tar.gz" ]; then
                log_message "Downloaded Metamod file is empty or not found." "error"
                return 1
            fi

            mkdir -p "$TEMP_DIR/metamod"
            log_message "Extracting Metamod archive..." "running"

            tar -xzf "$TEMP_DIR/metamod.tar.gz" -C "$TEMP_DIR/metamod" || {
                log_message "Failed to extract Metamod archive. Skipping update." "error"
                return 1
            }

            log_message "Copying files to $OUTPUT_DIR..." "running"
            cp -rf "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/"

            update_version_file "Metamod" "$new_version"
            log_message "Metamod update completed successfully." "success"
        else
            log_message "No new version of Metamod available. Skipping update." "success"
        fi
    fi
}

update_counterstrikesharp() {
    if [ "$CSS_AUTOUPDATE" = "1" ]; then
        log_message "Updating CounterStrikeSharp..." "running"
        update_addon "roflmuffin/CounterStrikeSharp" "$OUTPUT_DIR" "css" "CSS"
    fi
}

get_current_version() {
    local addon="$1"
    if [ -f "$VERSION_FILE" ]; then
        grep "^$addon=" "$VERSION_FILE" | cut -d'=' -f2
    else
        echo ""
    fi
}

update_version_file() {
    local addon="$1"
    local new_version="$2"
    if grep -q "^$addon=" "$VERSION_FILE"; then
        sed -i "s/^$addon=.*/$addon=$new_version/" "$VERSION_FILE"
    else
        echo "$addon=$new_version" >> "$VERSION_FILE"
    fi
}