#!/bin/bash

source /scripts/install.sh
source /scripts/cleanup.sh
source /scripts/update.sh
source /scripts/filter.sh

# Enhanced error handling
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

cd /home/container
sleep 1

# Get internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')

# Initial setup and sync
install_steamcmd
clean_old_logs

# Server update process
if [ ! -z ${SRCDS_APPID} ] && [ ${SRCDS_STOP_UPDATE:-0} -eq 0 ]; then
    log_message "Starting SteamCMD for AppID: ${SRCDS_APPID}" "running"

    STEAMCMD=""
    if [ ! -z ${SRCDS_BETAID} ]; then
        if [ ! -z ${SRCDS_BETAPASS} ]; then
            if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                log_message "SteamCMD Validate Flag Enabled! Triggered install validation for AppID: ${SRCDS_APPID}" "error"
                log_message "THIS MAY WIPE CUSTOM CONFIGURATIONS! Please stop the server if this was not intended." "error"
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} validate +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} validate +quit"
                fi
            else
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} +quit"
                fi
            fi
        else
            if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} validate +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} validate +quit"
                fi
            else
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
                fi
            fi
        fi
    else
        if [ ${SRCDS_VALIDATE} -eq 1 ]; then
        log_message "SteamCMD Validate Flag Enabled! Triggered install validation for AppID: ${SRCDS_APPID}" "error"
        log_message "THIS MAY WIPE CUSTOM CONFIGURATIONS! Please stop the server if this was not intended." "error"
            if [ ! -z ${SRCDS_LOGIN} ]; then
                STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} validate +quit"
            else
                STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} validate +quit"
            fi
        else
            if [ ! -z ${SRCDS_LOGIN} ]; then
                STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
            else
                STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
            fi
        fi
    fi

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