#!/bin/bash

# testable: local test harness pre-defines log_message and skips the image-only source
if ! declare -F log_message >/dev/null 2>&1; then
    source /utils/logging.sh
fi

# ! TODO: Remove SYNC_LOCATION fallback after 2026-10-01 (legacy sync deprecated)
# ! TODO: Remove legacy .daemon-managed / .daemon-push-active handling after
# !       2026-10-01 (compat for host scripts < 1.0.49, deprecated 2026-07-23)

# Priority: daemon > SYNC_LOCATION > SteamCMD
# Sets SRCDS_STOP_UPDATE=1 if daemon ready, else falls through.
#
# Status-file protocol (host script >= 1.0.49): the daemon writes
# egg/.daemon-status (state=/ts=/queue_pos= lines) and the egg ONLY READS it -
# nothing is deleted, so the old delete-vs-touch boot race cannot happen.
#   done/failed  -> accepted only when ts >= EGG_BOOT_EPOCH (ack for THIS boot)
#   queued/updating/verifying/pushing -> wait while ts stays fresh (daemon
#                   refreshes every 3s; stale ts = dead daemon = fallback)
# Legacy marker protocol (older host scripts) is used only while no fresh
# status file exists.
detect_daemon_vpk() {
    # SRCDS_STOP_UPDATE=1 is a panel-level flag for disabling SteamCMD, NOT for
    # skipping daemon detection. Daemon path must always run.
    local status_file="${EGG_DIR}/.daemon-status"
    local marker="${EGG_DIR}/.daemon-managed"
    local push_active="${EGG_DIR}/.daemon-push-active"
    local csgo_dir="${GAME_CSGO_DIR:-/home/container/game/csgo}"
    local boot_epoch="${EGG_BOOT_EPOCH:-$(date +%s)}"
    local stale_secs="${DAEMON_STATUS_STALE_SECS:-20}"
    local wait_max_secs="${DAEMON_WAIT_MAX_SECS:-20}"
    local announce_after_secs="${DAEMON_WAIT_SECS:-2}"

    # test hook: simulate a slow container boot (race repro, see #56)
    if [[ "${DAEMON_TEST_BOOT_DELAY:-0}" =~ ^[0-9]+$ ]] && [ "${DAEMON_TEST_BOOT_DELAY:-0}" -gt 0 ]; then
        log_message "Test hook: delaying boot by ${DAEMON_TEST_BOOT_DELAY}s (DAEMON_TEST_BOOT_DELAY)" "warning"
        sleep "$DAEMON_TEST_BOOT_DELAY"
    fi

    _vpk_info() {
        local n s
        n=$(find -L "$csgo_dir" -maxdepth 3 -name "*.vpk" -type f 2>/dev/null | wc -l)
        s=$(find -L "$csgo_dir" -maxdepth 3 -name "*.vpk" -type f -printf "%s\n" 2>/dev/null \
            | awk '{s+=$1} END {printf "%.1f GB", s/1073741824}')
        echo "${n} files, ${s}"
    }

    _daemon_managed() {
        export DAEMON_EVIDENCE_FOUND=1
        if [ "${SYNC_LOCATION+defined}" = "defined" ]; then
            log_message "Daemon detected - ignoring deprecated SYNC_LOCATION variable" "info"
            log_message "  → Remove SYNC_LOCATION from startup variables to silence this notice" "info"
        fi
        log_message "Daemon-managed ($(_vpk_info))" "info"
        SRCDS_STOP_UPDATE=1
    }

    local standalone_grace_secs="${DAEMON_STANDALONE_GRACE_SECS:-5}"
    local legacy_grace_secs="${DAEMON_LEGACY_GRACE_SECS:-5}"
    local steamapps_dir="${EGG_STEAMAPPS_DIR:-/home/container/steamapps}"
    local waited=0 announced=false last_note="" saw_status=false marker_ticks=0
    local state ts qpos now age
    while :; do
        state=""; ts=0; qpos=""
        if [ -f "$status_file" ]; then
            saw_status=true
            state=$(grep -m1 '^state=' "$status_file" 2>/dev/null | cut -d= -f2)
            ts=$(grep -m1 '^ts=' "$status_file" 2>/dev/null | cut -d= -f2)
            qpos=$(grep -m1 '^queue_pos=' "$status_file" 2>/dev/null | cut -d= -f2)
            [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
        fi
        now=$(date +%s)
        age=$((now - ts))

        # terminal states: only an ack written after THIS boot counts, so a
        # pre-restart "done" can't start the server on files mid-replacement
        if [ "$ts" -ge "$boot_epoch" ]; then
            if [ "$state" = "done" ]; then
                # sanity: daemon says ready but not a single VPK is readable
                # (e.g. dangling symlinks after a failed mount) -> rebuild locally
                if [ -z "$(find -L "$csgo_dir" -maxdepth 3 -name "*.vpk" -type f -print 2>/dev/null | head -n 1)" ]; then
                    log_warn_code "KL-DMN-04" "Daemon reported ready but no readable VPK found - falling back to SteamCMD" \
                        "Check the daemon mount: sudo journalctl -u cs2-vpk-daemon -n 100 | grep nsenter"
                    return 0
                fi
                _daemon_managed
                return 0
            fi
            if [ "$state" = "failed" ]; then
                log_warn_code "KL-DMN-03" "Daemon reported a failed push - falling back to SteamCMD" \
                    "Check daemon logs on the host: sudo journalctl -u cs2-vpk-daemon -n 100"
                return 0
            fi
        fi

        # live non-terminal status: daemon is talking to us, keep waiting and
        # show progress; skip the legacy checks while the new protocol is active
        if [ "$age" -le "$stale_secs" ] && [ -n "$state" ]; then
            local note=""
            case "$state" in
                queued)    note="queued:${qpos}" ;;
                updating)  note="updating" ;;
                verifying) note="verifying" ;;
                pushing)   note="pushing" ;;
                done|failed) note="preboot-terminal" ;;  # fresh, but from before this boot: wait for our ack
            esac
            if [ -n "$note" ]; then
                if [ "$note" != "$last_note" ]; then
                    case "$state" in
                        queued)
                            if [[ "$qpos" =~ ^[0-9]+$ ]] && [ "$qpos" -gt 1 ]; then
                                log_message "Waiting for game files - $((qpos - 1)) server(s) ahead in queue..." "running"
                            else
                                log_message "Waiting in daemon queue for game files..." "running"
                            fi
                            ;;
                        updating)  log_message "Central CS2 update in progress - waiting for it to finish..." "running" ;;
                        verifying) log_message "Daemon is verifying game files..." "running" ;;
                        pushing)   log_message "Daemon is copying game files..." "running" ;;
                    esac
                    last_note="$note"
                fi
                waited=0
                sleep 1
                continue
            fi
        fi

        # legacy protocol (host script < 1.0.49): marker touched after the
        # boot-time deletion = daemon alive and files ready. Grace period first:
        # a NEW script touches the marker instantly (compat) while its worker's
        # first status write lands ~1-2s later - the status protocol gets first
        # claim, the bare marker only counts once it stayed alone for the grace.
        if [ -f "$marker" ]; then
            marker_ticks=$((marker_ticks + 1))
            if [ "$marker_ticks" -gt "$legacy_grace_secs" ]; then
                # old scripts never write a status file - warn only in that case, so
                # a new-script host (stale status + cron push) doesn't get a false alarm
                if [ ! -f "$status_file" ]; then
                    log_message "Host update script is outdated (legacy daemon protocol) - support ends after 2026-10-01" "warning"
                    log_message "  → It self-updates if AUTO_UPDATE_SCRIPT=true; otherwise re-run the installer on the host" "warning"
                fi
                _daemon_managed
                return 0
            fi
            sleep 1
            continue
        fi
        # legacy long-push heartbeat: keep waiting while it stays fresh
        if [ -n "$(find "$push_active" -mmin -2 2>/dev/null)" ]; then
            if [ "$last_note" != "legacy-push" ]; then
                log_message "Daemon push still in progress - waiting for it to finish..." "running"
                last_note="legacy-push"
            fi
            waited=0
            sleep 1
            continue
        fi

        # standalone shortcut: an established SteamCMD install with zero daemon
        # evidence (no status file ever, no marker, no shared mount) doesn't need
        # the full window - a live daemon signals within 1-3s of the start event
        if ! $saw_status && [ "$waited" -ge "$standalone_grace_secs" ] && \
           [ ! -d /tmp/cs2-shared ] && [ -d "$steamapps_dir" ]; then
            break
        fi
        [ "$waited" -ge "$wait_max_secs" ] && break
        sleep 1
        waited=$((waited + 1))
        if ! $announced && [ "$waited" -ge "$announce_after_secs" ]; then
            log_message "Checking for daemon-managed game files..." "running"
            announced=true
        fi
    done

    # no daemon signal within the window -> SteamCMD path
    if [ "${SYNC_LOCATION+defined}" = "defined" ]; then
        log_message "⚠️  DEPRECATION WARNING ⚠️" "warning"
        log_message "SYNC_LOCATION is deprecated and will be removed after 2026-10-01!" "warning"
        log_message "  → Import the latest egg - it will clean this up automatically." "warning"
        log_message "  → Install daemon: curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/install-cs2-update.sh -o /tmp/install-cs2-update.sh && sudo bash /tmp/install-cs2-update.sh" "warning"
    fi
    return 0
}

# Fallback hygiene: a daemon-managed volume that lost its daemon leaves dangling
# VPK symlinks behind (shared mount gone). SteamCMD would choke on them, so drop
# broken links before it runs - resolving links are left untouched.
cleanup_broken_vpk_symlinks() {
    [ "${SRCDS_STOP_UPDATE:-0}" -eq 1 ] && return 0
    local game_dir="${GAME_DIR:-/home/container/game}"
    [ -d "$game_dir" ] || return 0
    local removed
    removed=$(find "$game_dir" -name '*.vpk' -type l ! -exec test -e {} \; -print -delete 2>/dev/null | wc -l | tr -d ' ')
    if [ "${removed:-0}" -gt 0 ]; then
        log_message "Removed ${removed} broken VPK symlink(s) left by a previous daemon setup" "warning"
    fi
    return 0
}

# Remove local SteamCMD artifacts when daemon is authoritative: saves ~200MB + cleans
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

export -f detect_daemon_vpk cleanup_daemon_mode cleanup_broken_vpk_symlinks
