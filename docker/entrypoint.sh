#!/bin/bash

source /utils/logging.sh
source /utils/config.sh
source /scripts/install.sh
source /scripts/sync.sh
source /scripts/cleanup.sh
source /scripts/update.sh
source /scripts/filter.sh
source /scripts/update_helper.sh

# Enhanced error handling
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

cd /home/container
sleep 1

# Initialize and load configurations
init_configs
load_configs

# Get internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')

detect_daemon_vpk
cleanup_daemon_mode

# Legacy VPK sync (SYNC_LOCATION mode) - runs before daemon detection result check
if [ ${SRCDS_STOP_UPDATE:-0} -eq 0 ]; then
    sync_files
    sync_cfg_files
fi

# SteamCMD install and cleanup (skip if VPKs managed externally)
if [ ${SRCDS_STOP_UPDATE:-0} -eq 0 ]; then
    install_steamcmd
fi

rotate_logs

# Server update process
if [ -n "${SRCDS_APPID}" ] && [ "${SRCDS_STOP_UPDATE:-0}" -eq 0 ]; then
    # Build SteamCMD command from optional parts — login, beta, validate.
    STEAMCMD="./steamcmd/steamcmd.sh"

    if [ -n "${SRCDS_LOGIN}" ]; then
        STEAMCMD+=" +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS}"
    else
        STEAMCMD+=" +login anonymous"
    fi

    STEAMCMD+=" +force_install_dir /home/container +app_update ${SRCDS_APPID}"

    if [ -n "${SRCDS_BETAID}" ]; then
        STEAMCMD+=" -beta ${SRCDS_BETAID}"
        if [ -n "${SRCDS_BETAPASS}" ]; then
            STEAMCMD+=" -betapassword ${SRCDS_BETAPASS}"
        fi
    fi

    if [ "${SRCDS_VALIDATE}" -eq 1 ]; then
        STEAMCMD+=" validate"
        log_message "⚠ VALIDATION ENABLED: THIS MAY WIPE CUSTOM CONFIGURATIONS!" "error"
        log_message "  → Starting in 5 seconds — stop the server NOW to abort." "warning"
        sleep 5
    fi

    STEAMCMD+=" +quit"

    log_message "SteamCMD command: $(echo "$STEAMCMD" | sed -E 's/(\+login [^ ]+ )[^ ]+/\1****/')" "debug"

    trap - ERR
    eval ${STEAMCMD}
    STEAM_EXIT_CODE=$?
    trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

    if [ $STEAM_EXIT_CODE -eq 8 ]; then
        log_error_code "KL-STM-01" "SteamCMD connection error (exit code 8)"
    elif [ $STEAM_EXIT_CODE -ne 0 ]; then
        log_error_code "KL-STM-02" "SteamCMD failed with exit code $STEAM_EXIT_CODE"
    fi

    # Update steamclient.so files
    cp -f ./steamcmd/linux32/steamclient.so ./.steam/sdk32/steamclient.so
    cp -f ./steamcmd/linux64/steamclient.so ./.steam/sdk64/steamclient.so
fi

# Handle the addon installations based on the selection
update_addons

# Set up console filter
setup_message_filter

# Build the actual startup command from template
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))

log_message "Starting server: ${MODIFIED_STARTUP}" "info"

# GDB mode: use Valve's built-in GAME_DEBUGGER support (cs2.sh line 106)
# gdbserver launches cs2 as parent process, so no SYS_PTRACE capability needed
if [ -n "${GDB_DEBUG_PORT}" ] && [ "${GDB_DEBUG_PORT}" != "0" ]; then
    export GAME_DEBUGGER="gdbserver --no-disable-randomization :${GDB_DEBUG_PORT}"
    log_message "GDB mode: Server will start under gdbserver on port ${GDB_DEBUG_PORT}" "info"
    log_message "Server will wait for debugger connection before starting" "warning"
fi

# Actually start the server and handle its output
START_CMD="script -qfc \"$MODIFIED_STARTUP\" /dev/null 2>&1"

eval "$START_CMD" | while IFS= read -r line; do
    line="${line%[[:space:]]}"
    [[ "$line" =~ Segmentation\ fault.*"${GAMEEXE}" ]] && continue

    # Detect crash via cs2.sh crash message pattern
    if [[ "$line" =~ \./game/cs2\.sh:.*Aborted.*\(core\ dumped\) ]]; then
        handle_server_output "$line"
        log_warn_code "KL-SRV-01" "Server crash detected" \
            "Review stack trace above for the failing module" \
            "Common causes: outdated addons, plugin incompatibility, stale gamedata"
        continue
    fi

    handle_server_output "$line"
done

# Clean up any background processes we started
pkill -P $$ 2>/dev/null || true

log_message "Server stopped" "success"