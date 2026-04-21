#!/bin/bash

source /utils/logging.sh

# ! TODO: Remove SYNC_LOCATION fallback after 2026-10-01 (legacy sync deprecated)

# Priority: daemon marker > SYNC_LOCATION > local SteamCMD
# Detects daemon-managed VPK files via the heartbeat marker and sets SRCDS_STOP_UPDATE=1
# when the daemon is active. If daemon evidence is found, SYNC_LOCATION is ignored
# (a leftover variable should not disable the daemon path).
detect_daemon_vpk() {
    [ "${SRCDS_STOP_UPDATE:-0}" -eq 1 ] && return 0

    local marker="/home/container/egg/.daemon-managed"
    local mount="/tmp/cs2-shared"
    local ttl="${DAEMON_MARKER_TTL:-600}"
    local silent_secs="${DAEMON_WAIT_SECS:-2}"
    local silent_ticks=$((silent_secs * 10))
    local mount_max_secs="${DAEMON_MOUNT_WAIT_SECS:-30}"

    _is_mounted() { awk -v m="$1" '$5 == m {f=1} END {exit !f}' /proc/self/mountinfo 2>/dev/null; }
    _has_vpk_symlinks() { find /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type l 2>/dev/null | grep -q .; }
    _vpk_info() {
        local n s
        n=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | wc -l)
        s=$(find -L /home/container/game/csgo -maxdepth 3 -name "*.vpk" -type f -printf "%s\n" 2>/dev/null \
            | awk '{s+=$1} END {printf "%.1f GB", s/1073741824}')
        echo "${n} files, ${s}"
    }

    # Silent probe for daemon signal (first-boot race). Skip: legacy SYNC_LOCATION or =0.
    if [ "${SYNC_LOCATION+defined}" != "defined" ] && [ ! -f "$marker" ] && ! _is_mounted "$mount"; then
        local t=0
        while [ "$t" -lt "$silent_ticks" ]; do
            [ -f "$marker" ] && break
            _is_mounted "$mount" && break
            sleep 0.1
            ((t++)) || true
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

    local age=$(( $(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || echo 0) ))
    if [ "$age" -ge "$ttl" ]; then
        log_warn_code "KL-DMN-01" "Daemon marker stale (${age}s > ${ttl}s) - daemon dead? falling back to SteamCMD" \
            "Check: journalctl -u cs2-vpk-daemon -n 50"
        # Purge daemon artifacts — broken VPK symlinks → /tmp/cs2-shared crash CS2 on load.
        unset DAEMON_EVIDENCE_FOUND
        rm -f "$marker" 2>/dev/null || true
        local cleaned
        cleaned=$(find /home/container/game/csgo -type l -lname '/tmp/cs2-shared/*' -print -delete 2>/dev/null | wc -l)
        if [ "${cleaned:-0}" -gt 0 ]; then
            log_message "  → Removed ${cleaned} broken VPK symlink(s)" "success"
        fi
        return 0
    fi

    # Mount wait: announce only after silent window → fast mounts stay quiet.
    if _has_vpk_symlinks && ! _is_mounted "$mount"; then
        local t=0 max_t=$((mount_max_secs * 10)) announced=false
        while ! _is_mounted "$mount"; do
            if [ "$t" -ge "$max_t" ]; then
                log_error_code "KL-DMN-02" "Daemon mount wait timed out after $((t/10))s - server WILL fail to load game files" \
                    "Check: journalctl -u cs2-vpk-daemon -n 50"
                return 0
            fi
            sleep 0.1
            ((t++)) || true
            if ! $announced && [ "$t" -ge "$silent_ticks" ]; then
                log_message "Waiting for daemon synchronization..." "info"
                announced=true
            fi
            $announced && [ $((t % 50)) -eq 0 ] \
                && log_message "  Still waiting for daemon mount... ($((t/10))s/${mount_max_secs}s)" "info"
        done
    fi

    log_message "Daemon-managed (heartbeat: ${age}s/${ttl}s, $(_vpk_info))" "info"
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
