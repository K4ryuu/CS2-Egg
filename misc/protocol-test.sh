#!/bin/bash
# Self-contained check for the egg<->daemon boot handshake (detect_daemon_vpk).
# No docker/root needed: paths come from EGG_DIR / GAME_CSGO_DIR overrides and
# the timing windows are shortened via DAEMON_* env vars. Run: bash this file.
set -u

HELPER="$(cd "$(dirname "$0")/.." && pwd)/docker/scripts/update_helper.sh"
FAILS=0

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\e[32m'; RED=$'\e[31m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    GREEN=""; RED=""; BOLD=""; RESET=""
fi

echo ""

# write_status <dir> <state> <ts> [queue_pos]
write_status() {
    { echo "state=$2"; echo "ts=$3"; [ -n "${4:-}" ] && echo "queue_pos=$4"; } > "$1/.daemon-status"
}

# run_case <name> <expected: managed|fallback> <setup-fn> [expected-log-substring]
# Prefix the log substring with "!" to assert it must NOT appear.
run_case() {
    local name="$1" expect="$2" setup="$3" expect_log="${4:-}"
    local tmp result
    tmp=$(mktemp -d)
    result=$(
        export EGG_DIR="$tmp/egg" GAME_CSGO_DIR="$tmp/csgo" LOG_OUT="$tmp/log"
        export DAEMON_STATUS_STALE_SECS=2 DAEMON_WAIT_MAX_SECS=2 DAEMON_WAIT_SECS=1 DAEMON_LEGACY_GRACE_SECS=2
        unset SRCDS_STOP_UPDATE DAEMON_EVIDENCE_FOUND SYNC_LOCATION EGG_BOOT_EPOCH 2>/dev/null
        mkdir -p "$EGG_DIR" "$GAME_CSGO_DIR"
        touch "$LOG_OUT"
        log_message() { echo "[$2] $1" >> "$LOG_OUT"; }
        log_warn_code() { echo "[$1] $2" >> "$LOG_OUT"; }
        "$setup" "$tmp"
        source "$HELPER"
        detect_daemon_vpk >/dev/null 2>&1
        [ "${SRCDS_STOP_UPDATE:-0}" = "1" ] && echo -n "managed" || echo -n "fallback"
    )
    local ok=true
    [ "$result" = "$expect" ] || ok=false
    if [ -n "$expect_log" ]; then
        if [ "${expect_log#!}" != "$expect_log" ]; then
            grep -q "${expect_log#!}" "$tmp/log" 2>/dev/null && ok=false
        elif ! grep -q "$expect_log" "$tmp/log" 2>/dev/null; then
            ok=false
        fi
    fi
    if $ok; then
        echo "${GREEN}PASS${RESET}  $name"
    else
        echo "${RED}FAIL${RESET}  $name (got: $result, expected: $expect${expect_log:+, log must contain '$expect_log'})"
        sed 's/^/      | /' "$tmp/log" 2>/dev/null
        FAILS=$((FAILS + 1))
    fi
    rm -rf "$tmp"
}

future_ts() { echo $(($(date +%s) + 30)); }

# --- scenarios --------------------------------------------------------------

s_done_fresh() {
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    write_status "$EGG_DIR" done "$(future_ts)"
}

s_failed_fresh() {
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    write_status "$EGG_DIR" failed "$(future_ts)"
}

s_queued_then_done() {
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    write_status "$EGG_DIR" queued "$(future_ts)" 3
    ( sleep 2; write_status "$EGG_DIR" done "$(future_ts)" ) &
}

s_no_signal() { :; }

s_preboot_done_only() {
    # boot happened "later" than the ack: done must NOT be accepted
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    export EGG_BOOT_EPOCH=$(($(date +%s) + 1000))
    write_status "$EGG_DIR" done "$(date +%s)"
}

s_legacy_marker() {
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    touch "$EGG_DIR/.daemon-managed"
}

s_done_no_vpk() {
    write_status "$EGG_DIR" done "$(future_ts)"
}

s_stale_queued() {
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    write_status "$EGG_DIR" queued "$(($(date +%s) - 100))" 2
}

s_marker_races_status() {
    # new-script host: compat marker lands instantly, worker status ~1-2s later -
    # the status protocol must win and no legacy deprecation warning may appear
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    touch "$EGG_DIR/.daemon-managed"
    ( sleep 1; write_status "$EGG_DIR" queued "$(future_ts)" 1
      sleep 1; write_status "$EGG_DIR" done "$(future_ts)" ) &
}

s_updating_then_done() {
    # restart during a central CS2 update: egg must wait it out, then start
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    write_status "$EGG_DIR" updating "$(future_ts)"
    ( sleep 2; write_status "$EGG_DIR" done "$(future_ts)" ) &
}

s_pushing_then_failed() {
    # push dies mid-boot: failed ack must drop the egg to SteamCMD immediately
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    write_status "$EGG_DIR" pushing "$(future_ts)"
    ( sleep 2; write_status "$EGG_DIR" failed "$(future_ts)" ) &
}

s_legacy_push_heartbeat() {
    # old-script long push: fresh heartbeat extends the wait past wait_max,
    # marker lands later and the boot still ends up daemon-managed
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    touch "$EGG_DIR/.daemon-push-active"
    ( sleep 3; touch "$EGG_DIR/.daemon-managed" ) &
}

s_queue_position_shown() {
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    write_status "$EGG_DIR" queued "$(future_ts)" 3
    ( sleep 2; write_status "$EGG_DIR" done "$(future_ts)" ) &
}

s_corrupt_status() {
    # garbage status file = no usable signal, must time out to SteamCMD
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    printf 'state=;;;\nts=not-a-number\n\x00\x01' > "$EGG_DIR/.daemon-status"
}

s_sync_location_fallback() {
    export SYNC_LOCATION="/nonexistent-legacy-mount"
}

s_preboot_failed_ignored() {
    # failed from BEFORE this boot is not ours to act on - no instant fallback,
    # the normal wait window decides
    touch "$GAME_CSGO_DIR/pak01_dir.vpk"
    export EGG_BOOT_EPOCH=$(($(date +%s) + 1000))
    write_status "$EGG_DIR" failed "$(date +%s)"
}

# --- run --------------------------------------------------------------------

run_case "done (this boot) -> managed"                managed  s_done_fresh
run_case "failed (this boot) -> instant fallback"     fallback s_failed_fresh "KL-DMN-03"
run_case "queued -> done flip -> managed"             managed  s_queued_then_done
run_case "no signal -> timeout fallback"              fallback s_no_signal
run_case "pre-boot done not accepted -> fallback"     fallback s_preboot_done_only
run_case "legacy marker -> managed + deprecation"     managed  s_legacy_marker "2026-10-01"
run_case "done but zero readable VPK -> fallback"     fallback s_done_no_vpk "KL-DMN-04"
run_case "stale queued (dead daemon) -> fallback"     fallback s_stale_queued
run_case "marker races status -> status wins"         managed  s_marker_races_status "!2026-10-01"
run_case "updating -> waits out central update"       managed  s_updating_then_done "Central CS2 update in progress"
run_case "pushing -> failed mid-boot -> fallback"     fallback s_pushing_then_failed "KL-DMN-03"
run_case "legacy push heartbeat extends the wait"     managed  s_legacy_push_heartbeat "Daemon push still in progress"
run_case "queue position shown on console"            managed  s_queue_position_shown "2 server(s) ahead"
run_case "corrupt status file -> timeout fallback"    fallback s_corrupt_status
run_case "SYNC_LOCATION fallback warns deprecation"   fallback s_sync_location_fallback "DEPRECATION"
run_case "pre-boot failed ignored (no instant fall)"  fallback s_preboot_failed_ignored "!KL-DMN-03"

# --- bespoke cases ----------------------------------------------------------

# standalone shortcut: established SteamCMD install + zero daemon evidence must
# give up well before the full wait window
tmp=$(mktemp -d)
start=$SECONDS
result=$(
    export EGG_DIR="$tmp/egg" GAME_CSGO_DIR="$tmp/csgo" EGG_STEAMAPPS_DIR="$tmp/steamapps"
    export DAEMON_STATUS_STALE_SECS=2 DAEMON_WAIT_MAX_SECS=15 DAEMON_STANDALONE_GRACE_SECS=1 DAEMON_WAIT_SECS=1
    unset SRCDS_STOP_UPDATE DAEMON_EVIDENCE_FOUND SYNC_LOCATION EGG_BOOT_EPOCH 2>/dev/null
    mkdir -p "$EGG_DIR" "$GAME_CSGO_DIR" "$EGG_STEAMAPPS_DIR"
    log_message() { :; }
    log_warn_code() { :; }
    source "$HELPER"
    detect_daemon_vpk >/dev/null 2>&1
    [ "${SRCDS_STOP_UPDATE:-0}" = "1" ] && echo -n "managed" || echo -n "fallback"
)
elapsed=$((SECONDS - start))
if [ "$result" = "fallback" ] && [ "$elapsed" -le 8 ]; then
    echo "${GREEN}PASS${RESET}  standalone steamapps -> fast fallback (${elapsed}s)"
else
    echo "${RED}FAIL${RESET}  standalone steamapps -> fast fallback (result=$result, elapsed=${elapsed}s)"
    FAILS=$((FAILS + 1))
fi
rm -rf "$tmp"

# broken VPK symlink cleanup: dangling links removed, resolving links kept
tmp=$(mktemp -d)
if (
    export GAME_DIR="$tmp/game"
    mkdir -p "$GAME_DIR/csgo"
    echo x > "$tmp/real.vpk"
    ln -s "$tmp/real.vpk" "$GAME_DIR/csgo/ok.vpk"
    ln -s "$tmp/missing.vpk" "$GAME_DIR/csgo/broken.vpk"
    log_message() { :; }
    log_warn_code() { :; }
    unset SRCDS_STOP_UPDATE 2>/dev/null
    source "$HELPER"
    cleanup_broken_vpk_symlinks >/dev/null 2>&1
    [ -L "$GAME_DIR/csgo/ok.vpk" ] && [ ! -L "$GAME_DIR/csgo/broken.vpk" ]
); then
    echo "${GREEN}PASS${RESET}  broken VPK symlinks cleaned, valid ones kept"
else
    echo "${RED}FAIL${RESET}  broken VPK symlinks cleaned, valid ones kept"
    FAILS=$((FAILS + 1))
fi
rm -rf "$tmp"

# --- daemon-side units (centralized script sourced, main() stays dormant) ----

CENTRAL="$(cd "$(dirname "$0")" && pwd)/update-cs2-centralized.sh"

# dynamic volume ownership: uid:gid read from the volume dir, empty when unknown
if (
    source "$CENTRAL" >/dev/null 2>&1
    set +e
    tmp2=$(mktemp -d)
    own=$(_volume_owner "$tmp2")
    none=$(_volume_owner "$tmp2/nonexistent")
    rm -rf "$tmp2"
    [ "$own" = "$(id -u):$(id -g)" ] && [ -z "$none" ]
); then
    echo "${GREEN}PASS${RESET}  volume owner detected dynamically (uid:gid)"
else
    echo "${RED}FAIL${RESET}  volume owner detected dynamically (uid:gid)"
    FAILS=$((FAILS + 1))
fi

# status writers need flock (Linux); skipped on dev machines without it
if command -v flock >/dev/null 2>&1; then
    if (
        source "$CENTRAL" >/dev/null 2>&1
        set +e
        tmp2=$(mktemp -d)
        vol="$tmp2/vol"; mkdir -p "$vol/egg"
        c="test-$$-$RANDOM"
        _write_status "$c" "$vol" queued 3
        s1=$(grep -m1 '^state=' "$vol/egg/.daemon-status" | cut -d= -f2)
        p1=$(grep -m1 '^queue_pos=' "$vol/egg/.daemon-status" | cut -d= -f2)
        _write_status "$c" "$vol" done
        _refresh_status_entry "$c" "$vol"        # must NOT resurrect a non-terminal state
        s2=$(grep -m1 '^state=' "$vol/egg/.daemon-status" | cut -d= -f2)
        rm -rf "$tmp2"; rm -f "/var/lock/cs2-vpk-status-${c}.lock" 2>/dev/null
        [ "$s1" = "queued" ] && [ "$p1" = "3" ] && [ "$s2" = "done" ]
    ); then
        echo "${GREEN}PASS${RESET}  status writes atomic, terminal state never resurrected"
    else
        echo "${RED}FAIL${RESET}  status writes atomic, terminal state never resurrected"
        FAILS=$((FAILS + 1))
    fi
else
    echo "SKIP  status writer units (no flock on this machine - runs on Linux hosts)"
fi

# push lock: dead-owner and pid-less corpses get stolen, a live owner is waited
# out (the stale July locks in #58 parked every worker on "queued" for weeks)
if (
    source "$CENTRAL" >/dev/null 2>&1
    set +e
    tmp2=$(mktemp -d)
    export PUSH_LOCK_STEAL_GRACE=2

    # dead owner pid -> stolen on the first pass
    dead_lock="$tmp2/dead.lock"; mkdir -p "$dead_lock"
    dead_pid=$(bash -c 'echo $$'); echo "$dead_pid" > "$dead_lock/pid"
    _acquire_push_lock "$dead_lock" 4 || exit 1
    [ "$(cat "$dead_lock/pid")" = "$BASHPID" ] || exit 1

    # no pid file (pre-1.0.53 lock) -> stolen once the grace passed
    bare_lock="$tmp2/bare.lock"; mkdir -p "$bare_lock"
    _acquire_push_lock "$bare_lock" 10 || exit 1

    # live owner -> not stolen, budget runs out instead
    live_lock="$tmp2/live.lock"; mkdir -p "$live_lock"; echo "$$" > "$live_lock/pid"
    _acquire_push_lock "$live_lock" 2 && exit 1
    [ "$(cat "$live_lock/pid")" = "$$" ] || exit 1

    # free path: lock taken and stamped with the caller pid
    free_lock="$tmp2/free.lock"
    _acquire_push_lock "$free_lock" 2 || exit 1
    [ "$(cat "$free_lock/pid")" = "$BASHPID" ] || exit 1

    rm -rf "$tmp2"
); then
    echo "${GREEN}PASS${RESET}  push lock steals dead/pid-less locks, waits out a live owner"
else
    echo "${RED}FAIL${RESET}  push lock steals dead/pid-less locks, waits out a live owner"
    FAILS=$((FAILS + 1))
fi

# stale link prune: VPKs dropped by a CS2 update leave dangling links in every
# volume, and the egg skips its own cleanup while the daemon is authoritative
if (
    source "$CENTRAL" >/dev/null 2>&1
    set +e
    tmp2=$(mktemp -d)
    CS2_DIR="$tmp2/shared"; vol="$tmp2/vol"
    mkdir -p "$CS2_DIR/game/csgo" "$vol/game/csgo"
    echo x > "$CS2_DIR/game/csgo/pak01_000.vpk"
    ln -s /tmp/cs2-shared/game/csgo/pak01_000.vpk "$vol/game/csgo/pak01_000.vpk"   # source exists
    ln -s /tmp/cs2-shared/game/csgo/gone_001.vpk  "$vol/game/csgo/gone_001.vpk"    # source removed
    ln -s /home/container/custom/pack.vpk "$vol/game/csgo/foreign.vpk"             # not ours, keep

    _prune_stale_vpk_links test-container "$vol" >/dev/null 2>&1

    [ -L "$vol/game/csgo/pak01_000.vpk" ] || exit 1
    [ -L "$vol/game/csgo/foreign.vpk" ] || exit 1
    [ -L "$vol/game/csgo/gone_001.vpk" ] && exit 1
    rm -rf "$tmp2"
); then
    echo "${GREEN}PASS${RESET}  stale VPK links pruned, live ones kept"
else
    echo "${RED}FAIL${RESET}  stale VPK links pruned, live ones kept"
    FAILS=$((FAILS + 1))
fi

# duplicate worker guard: a reconcile sweep and a real docker event both fire on
# a restart, and the second worker would only overwrite the first registration
if (
    source "$CENTRAL" >/dev/null 2>&1
    set +e
    DAEMON_REGISTRY_DIR=$(mktemp -d)
    c="test-$$-$RANDOM"

    _worker_registered_alive "$c" && exit 1              # no registration at all

    # stand-in worker: argv[0] carries the script name the /proc check looks for
    bash -c "exec -a $SCRIPT_FILENAME bash -c 'sleep 30'" &
    worker=$!
    echo "pid=$worker" > "$DAEMON_REGISTRY_DIR/$c"
    _worker_registered_alive "$c" || { kill "$worker" 2>/dev/null; exit 1; }

    kill "$worker" 2>/dev/null; wait "$worker" 2>/dev/null
    _worker_registered_alive "$c" && exit 1              # crashed worker

    # live pid, but an unrelated process recycled it (Linux only, needs procfs)
    if [ -r "/proc/$$/cmdline" ]; then
        echo "pid=$$" > "$DAEMON_REGISTRY_DIR/$c"
        _worker_registered_alive "$c" && exit 1
    fi

    rm -rf "$DAEMON_REGISTRY_DIR"
); then
    echo "${GREEN}PASS${RESET}  duplicate worker skipped only while the first is alive"
else
    echo "${RED}FAIL${RESET}  duplicate worker skipped only while the first is alive"
    FAILS=$((FAILS + 1))
fi

# daemon instance lock: a hand-started second daemon wipes the running one's
# worker registry, so the second start has to be refused
if command -v flock >/dev/null 2>&1; then
    if (
        set +e
        tmp2=$(mktemp -d)
        lock="$tmp2/daemon.lock"
        exec 8>"$lock"
        flock -n 8 || exit 1                              # first instance claims it
        ( exec 9>"$lock"; flock -n 9 ) && exit 1          # second must be refused
        exec 8>&-
        ( exec 9>"$lock"; flock -n 9 ) || exit 1          # free again after release
        rm -rf "$tmp2"
    ); then
        echo "${GREEN}PASS${RESET}  daemon instance lock refuses a second daemon"
    else
        echo "${RED}FAIL${RESET}  daemon instance lock refuses a second daemon"
        FAILS=$((FAILS + 1))
    fi
else
    echo "SKIP  daemon instance lock (no flock on this machine - runs on Linux hosts)"
fi

# the doctor scans /var/lock, which is a symlink to /run/lock on Debian/Ubuntu:
# without -H find never descends and the orphaned-lock cleanup finds nothing
if (
    set +e
    tmp2=$(mktemp -d)
    mkdir -p "$tmp2/real/cs2-vpk-push-test.lock"
    ln -s "$tmp2/real" "$tmp2/link"
    found=$(find -H "$tmp2/link" -maxdepth 1 -name 'cs2-vpk-push-*' -type d 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$tmp2"
    [ "$found" = "1" ]
); then
    echo "${GREEN}PASS${RESET}  lock scan descends into a symlinked /var/lock"
else
    echo "${RED}FAIL${RESET}  lock scan descends into a symlinked /var/lock"
    FAILS=$((FAILS + 1))
fi

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo "${GREEN}${BOLD}All cases passed.${RESET}"
else
    echo "${RED}${BOLD}$FAILS case(s) FAILED.${RESET}"
    exit 1
fi
