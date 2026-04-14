#!/bin/bash

source /utils/logging.sh

# ! TODO: Remove this entire file after 2026-10-01 (SYNC_LOCATION support dropped)

# Detects daemon-managed VPK files and sets SRCDS_STOP_UPDATE=1 if found.
# If SYNC_LOCATION is defined (legacy egg), shows deprecation warning and skips daemon detection.
detect_daemon_vpk() {
    [ "${SRCDS_STOP_UPDATE:-0}" -eq 1 ] && return 0

    if [ "${SYNC_LOCATION+defined}" = "defined" ]; then
        log_message "⚠️  DEPRECATION WARNING ⚠️" "warning"
        log_message "SYNC_LOCATION is deprecated and will be removed after 2026-10-01!" "warning"
        log_message "  → Import the latest egg - it will clean this up automatically." "warning"
        log_message "  → Install daemon: curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/install-cs2-update.sh | sudo bash" "warning"
        return 0
    fi

    _vpk_info() {
        local n s
        n=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | wc -l)
        s=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f -printf "%s\n" 2>/dev/null \
            | awk '{s+=$1} END {printf "%.1f GB", s/1073741824}')
        echo "${n} files, ${s}"
    }

    if find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | grep -q .; then
        log_message "VPK files detected ($(_vpk_info)) - centrally managed, skipping internal updates" "info"
        SRCDS_STOP_UPDATE=1
    elif find /home/container/game/csgo -maxdepth 3 -name "*.vpk" 2>/dev/null | grep -q .; then
        log_message "VPK files detected - waiting for daemon synchronization..." "info"
        local _waited=0
        while [ $_waited -lt 10 ]; do
            sleep 1; ((_waited++)) || true
            if find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | grep -q .; then
                log_message "Synchronized (${_waited}s) - $(_vpk_info) centrally managed, skipping internal updates" "info"
                SRCDS_STOP_UPDATE=1
                break
            fi
        done
        if [ "${SRCDS_STOP_UPDATE:-0}" -eq 0 ]; then
            log_message "Daemon sync timed out - daemon not running or mount failed." "warning"
            log_message "  → Check: journalctl -u cs2-vpk-daemon -n 50" "warning"
            log_message "  → Install: curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/install-cs2-update.sh | sudo bash" "warning"
        fi
    fi
}

# Removes local SteamCMD only when daemon VPKs are confirmed accessible.
cleanup_daemon_mode() {
    [ "${SYNC_LOCATION+defined}" = "defined" ] && return 0
    [ -d "/home/container/steamcmd" ] || return 0
    if find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | grep -q .; then
        log_message "Daemon mode active - removing local SteamCMD (not needed, saves ~200MB)" "info"
        rm -rf /home/container/steamcmd /home/container/steamapps /home/container/Steam
    fi
}

export -f detect_daemon_vpk cleanup_daemon_mode
