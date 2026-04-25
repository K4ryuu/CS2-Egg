#!/bin/bash

source /utils/logging.sh

# ! TODO: Remove SYNC_LOCATION fallback after 2026-10-01 (legacy sync deprecated)

# Priority: daemon > SYNC_LOCATION > SteamCMD
# Sets SRCDS_STOP_UPDATE=1 if daemon ready, else falls through.
detect_daemon_vpk() {
    # SRCDS_STOP_UPDATE=1 is a panel-level flag for disabling SteamCMD, NOT for
    # skipping daemon detection. Daemon path must always run.
    # entrypoint.sh deletes the marker at boot, so marker presence = fresh daemon push
    local marker="/home/container/egg/.daemon-managed"
    local wait_max_secs="${DAEMON_WAIT_MAX_SECS:-10}"
    local announce_after_secs="${DAEMON_WAIT_SECS:-2}"
    local announce_ticks=$((announce_after_secs * 10))

    _vpk_info() {
        local n s
        n=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | wc -l)
        s=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f -printf "%s\n" 2>/dev/null \
            | awk '{s+=$1} END {printf "%.1f GB", s/1073741824}')
        echo "${n} files, ${s}"
    }

    # wait for daemon to touch marker (= push done)
    if [ ! -f "$marker" ]; then
        local t=0 max_t=$((wait_max_secs * 10)) announced=false
        while [ ! -f "$marker" ]; do
            [ "$t" -ge "$max_t" ] && break
            sleep 0.1
            ((t++)) || true
            if ! $announced && [ "$t" -ge "$announce_ticks" ]; then
                log_message "Waiting for daemon to finish push..." "running"
                announced=true
            fi
        done
    fi

    if [ ! -f "$marker" ]; then
        if [ "${SYNC_LOCATION+defined}" = "defined" ]; then
            log_message "⚠️  DEPRECATION WARNING ⚠️" "warning"
            log_message "SYNC_LOCATION is deprecated and will be removed after 2026-10-01!" "warning"
            log_message "  → Import the latest egg - it will clean this up automatically." "warning"
            log_message "  → Install daemon: curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/install-cs2-update.sh -o /tmp/install-cs2-update.sh && sudo bash /tmp/install-cs2-update.sh" "warning"
        fi
        return 0
    fi

    export DAEMON_EVIDENCE_FOUND=1
    if [ "${SYNC_LOCATION+defined}" = "defined" ]; then
        log_message "Daemon detected - ignoring deprecated SYNC_LOCATION variable" "info"
        log_message "  → Remove SYNC_LOCATION from startup variables to silence this notice" "info"
    fi

    log_message "Daemon-managed ($(_vpk_info))" "info"
    SRCDS_STOP_UPDATE=1
}

# Remove local SteamCMD artifacts when daemon is authoritative — saves ~200MB + cleans
# stale dirs left over from a previous non-daemon boot.
cleanup_daemon_mode() {
    [ "${SRCDS_STOP_UPDATE:-0}" -eq 1 ] || return 0

    # steamcmd/ is the big one (~200MB); Steam/ and steamapps/ are smaller leftovers
    # with no purpose in daemon mode (game files come from the shared CS2_DIR mount).
    local targets=(
        /home/container/steamcmd
        /home/container/Steam
        /home/container/steamapps
    )
    local existing=()
    for t in "${targets[@]}"; do
        if [ -e "$t" ]; then
            existing+=("$t")
        fi
    done

    if [ ${#existing[@]} -eq 0 ]; then
        return 0
    fi

    log_message "Daemon mode active - removing ${#existing[@]} stale artifact(s)" "info"
    rm -rf "${existing[@]}" 2>/dev/null || true
}

export -f detect_daemon_vpk cleanup_daemon_mode
