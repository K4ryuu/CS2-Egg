#!/bin/bash

source /scripts/install.sh
source /scripts/cleanup.sh
source /scripts/update.sh
source /scripts/filter.sh

# Set error handling trap
trap 'handle_error' ERR

# Internal Docker IP
export INTERNAL_IP=`ip route get 1 | awk '{print $NF;exit}'`

# Server update process
if [ ! -z ${SRCDS_APPID} ]; then
    if [ ${SRCDS_STOP_UPDATE} -eq 0 ]; then
        STEAMCMD=""
        log_message "Starting SteamCMD for AppID: ${SRCDS_APPID}" "running"

        if [ ! -z ${SRCDS_BETAID} ]; then
            if [ ! -z ${SRCDS_BETAPASS} ]; then
                if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                    log_message "SteamCMD Validate Flag Enabled! Triggered install validation for AppID: ${SRCDS_APPID}" "running"
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
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
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
                        STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
                    else
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
                    fi
                fi
            fi
        else
            if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                log_message "SteamCMD Validate Flag Enabled! Triggered install validation for AppID: ${SRCDS_APPID}" "running"
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

        log_message "SteamCMD Launch: ${STEAMCMD}" "running"
        eval ${STEAMCMD}

        # Copy steamclient.so files
        cp -f ./steamcmd/linux32/steamclient.so ./.steam/sdk32/steamclient.so
        cp -f ./steamcmd/linux64/steamclient.so ./.steam/sdk64/steamclient.so
    fi
fi

# Run cleanup and update
cleanup_and_update

# Setup message filter
setup_message_filter

# Replace Startup Variables and censor Steam token
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))
MODIFIED_STARTUP="unbuffer -p ${MODIFIED_STARTUP}"

# Log the startup command with censored Steam token, without unbuffer -p
LOGGED_STARTUP=$(echo "${MODIFIED_STARTUP#unbuffer -p }" | sed -E 's/(\+sv_setsteamaccount\s+[A-Z0-9]{32})/+sv_setsteamaccount ************************/g')
log_message "Starting server with command: ${LOGGED_STARTUP}" "running"

# Run the Server
$MODIFIED_STARTUP 2>&1 | while IFS= read -r line; do
    line=$(echo -n "$line" | sed -e 's/[[:space:]]*$//')

    if [[ "$line" == *"Segmentation fault"* && "$line" == *"${GAMEEXE}"* ]]; then
        continue
    fi

    handle_server_output "$line"
done

# Kill background processes
if jobs -p &>/dev/null; then
    kill $(jobs -p) 2>/dev/null || true
fi

log_message "Server has stopped successfully." "success"