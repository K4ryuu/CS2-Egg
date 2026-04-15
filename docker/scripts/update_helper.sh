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

    local marker="/home/container/egg/.daemon-managed"
    local mount="/tmp/cs2-shared"
    local ttl="${DAEMON_MARKER_TTL:-600}"
    local max_wait="${DAEMON_WAIT_SECS:-15}"

    _vpk_info() {
        local n s
        n=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | wc -l)
        s=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f -printf "%s\n" 2>/dev/null \
            | awk '{s+=$1} END {printf "%.1f GB", s/1073741824}')
        echo "${n} files, ${s}"
    }
    _is_mounted() { awk -v m="$1" '$5 == m {f=1} END {exit !f}' /proc/self/mountinfo 2>/dev/null; }
    _has_vpk_symlinks() { find /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type l 2>/dev/null | grep -q .; }

    # Race protection: only wait if prior-daemon evidence exists.
    # Clean local install → no symlinks, no marker → instant return.
    local has_symlinks=0
    _has_vpk_symlinks && has_symlinks=1
    [ "$has_symlinks" -eq 0 ] && [ ! -f "$marker" ] && return 0

    local waited=0
    while :; do
        # Signal 1: mount (mandatory for symlink mode - re-mounted on docker start event)
        if _is_mounted "$mount"; then
            log_message "Daemon-managed ($(_vpk_info))" "info"
            SRCDS_STOP_UPDATE=1
            return 0
        fi
        # Signal 2: heartbeat marker - only trusted when no broken symlinks await mount
        if [ "$has_symlinks" -eq 0 ] && [ -f "$marker" ]; then
            local age=$(( $(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || echo 0) ))
            if [ "$age" -lt "$ttl" ]; then
                log_message "Daemon-managed (heartbeat: ${age}s/${ttl}s, $(_vpk_info))" "info"
                SRCDS_STOP_UPDATE=1
                return 0
            fi
            log_message "Daemon marker stale (${age}s > ${ttl}s) - daemon dead? falling back to SteamCMD" "warning"
            log_message "  → Check: journalctl -u cs2-vpk-daemon -n 50" "warning"
            return 0
        fi
        [ "$waited" -ge "$max_wait" ] && break
        sleep 1; ((waited++)) || true
    done

    log_message "Daemon detection timed out after ${max_wait}s" "warning"
    [ "$has_symlinks" -eq 1 ] && log_message "  → Symlink VPKs without mount - server WILL fail to load game files" "error"
    log_message "  → Check: journalctl -u cs2-vpk-daemon -n 50" "warning"
}

# Removes local SteamCMD only when daemon detection confirmed it.
cleanup_daemon_mode() {
    [ "${SYNC_LOCATION+defined}" = "defined" ] && return 0
    [ "${SRCDS_STOP_UPDATE:-0}" -eq 1 ] || return 0
    [ -d "/home/container/steamcmd" ] || return 0
    log_message "Daemon mode active - removing local SteamCMD (saves ~200MB)" "info"
    rm -rf /home/container/steamcmd /home/container/steamapps /home/container/Steam
}

export -f detect_daemon_vpk cleanup_daemon_mode
