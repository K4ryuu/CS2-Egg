#!/bin/bash

source /scripts/cleanup.sh
source /scripts/update.sh
source /scripts/filter.sh

# Enhanced error handling
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# Get internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')

# Function to build SteamCMD command
build_steamcmd_command() {
    local login_type="$1"
    local validate="$2"
    local beta="$3"
    local beta_pass="$4"

    local cmd="./steamcmd/steamcmd.sh"

    # Login section
    if [ ! -z "${SRCDS_LOGIN}" ] && [ "$login_type" = "auth" ]; then
        cmd+=" +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS}"
    else
        cmd+=" +login anonymous"
    fi

    # Common options
    cmd+=" +force_install_dir /home/container"

    # Beta handling
    if [ ! -z "$beta" ]; then
        cmd+=" -beta $beta"
        [ ! -z "$beta_pass" ] && cmd+=" -betapassword $beta_pass"
    fi

    # Validate if requested
    [ "$validate" = "1" ] && cmd+=" validate"

    cmd+=" +quit"
    echo "$cmd"
}

# Initial setup and sync
clean_old_logs

# Server update process
if [ ! -z ${SRCDS_APPID} ] && [ ${SRCDS_STOP_UPDATE:-0} -eq 0 ]; then
    log_message "Starting SteamCMD for AppID: ${SRCDS_APPID}" "running"

    if [ ${SRCDS_VALIDATE:-0} -eq 1 ]; then
        log_message "SteamCMD Validate Flag Enabled! This may overwrite custom configurations!" "error"
    fi

    STEAMCMD=$(build_steamcmd_command \
        "${SRCDS_LOGIN:+auth}" \
        "${SRCDS_VALIDATE:-0}" \
        "${SRCDS_BETAID}" \
        "${SRCDS_BETAPASS}")

    log_message "SteamCMD command: $(echo "$STEAMCMD" | sed -E 's/(\+login [^ ]+ )[^ ]+/\1****/')" "debug"
    eval ${STEAMCMD}

    # Update steamclient.so files
    cp -f ./steamcmd/linux32/steamclient.so ./.steam/sdk32/steamclient.so
    cp -f ./steamcmd/linux64/steamclient.so ./.steam/sdk64/steamclient.so

    configure_metamod
fi

# Run cleanup and setup message filter
cleanup_and_update
setup_message_filter

if [ "${UPDATE_AUTO_RESTART:-0}" -eq 1 ]; then
    log_message "Auto-restart is enabled. Server will restart automatically if a new version is detected." "running"
    version_check_loop &
fi

# Prepare startup command
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))
MODIFIED_STARTUP="unbuffer -p ${MODIFIED_STARTUP}"

# Log censored startup command
LOGGED_STARTUP=$(echo "${MODIFIED_STARTUP#unbuffer -p }" | \
    sed -E 's/(\+sv_setsteamaccount\s+[A-Z0-9]{32})/+sv_setsteamaccount ************************/g')
log_message "Starting server with command: ${LOGGED_STARTUP}" "running"

# Run the server with output handling
$MODIFIED_STARTUP 2>&1 | while IFS= read -r line; do
    line="${line%[[:space:]]}"
    [[ "$line" =~ Segmentation\ fault.*"${GAMEEXE}" ]] && continue
    handle_server_output "$line"
done

# Kill all background processes
pkill -P $$ 2>/dev/null || true

log_message "Server has stopped successfully." "success"