#!/bin/bash
source /utils/logging.sh

install_steamcmd() {
    if [ -f "./steamcmd/steamcmd.sh" ]; then
        log_message "SteamCMD is already installed" "debug"
        return 0
    fi

    log_message "Installing SteamCMD..." "running"
    local STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    local max_retries=3
    local retry=0

    # Set up default Steam credentials if not provided
    if [ "${STEAM_USER}" == "" ]; then
        STEAM_USER=anonymous
        STEAM_PASS=""
        STEAM_AUTH=""
    fi

    # Create necessary directories
    mkdir -p ./steamcmd
    mkdir -p ./steamapps

    # Download with retry
    while [ $retry -lt $max_retries ]; do
        if curl -sSL --connect-timeout 30 --max-time 300 -o steamcmd.tar.gz "$STEAMCMD_URL"; then
            break
        fi
        ((retry++))
        log_message "Download attempt $retry failed, retrying..." "error"
        sleep 5
    done

    if [ $retry -eq $max_retries ]; then
        log_message "Failed to download SteamCMD after $max_retries attempts" "error"
        return 1
    fi

    # Extract steamcmd
    if ! tar -xzvf steamcmd.tar.gz -C ./steamcmd; then
        log_message "Failed to extract SteamCMD" "error"
        return 1
    fi
    rm steamcmd.tar.gz
    # Set up required environment
    if [ ! -d "./steamcmd" ]; then
        log_message "steamcmd directory does not exist" "error"
        return 1
    fi

    # Initialize steamcmd
    ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} +app_update ${SRCDS_APPID} ${EXTRA_FLAGS} +quit

    # Set up 32-bit libraries
    mkdir -p ./.steam/sdk32
    cp -v ./steamcmd/linux32/steamclient.so ./.steam/sdk32/steamclient.so || {
        log_message "Failed to copy 32-bit libraries" "warning"
    }

    # Set up 64-bit libraries
    mkdir -p ./.steam/sdk64
    cp -v ./steamcmd/linux64/steamclient.so ./.steam/sdk64/steamclient.so || {
        log_message "Failed to copy 64-bit libraries" "warning"
    }

    log_message "SteamCMD installed successfully" "success"
    return 0
}