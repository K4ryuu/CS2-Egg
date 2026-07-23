#!/bin/bash
# Self-contained check for the egg<->daemon boot handshake (detect_daemon_vpk).
# No docker/root needed: paths come from EGG_DIR / GAME_CSGO_DIR overrides and
# the timing windows are shortened via DAEMON_* env vars. Run: bash this file.
set -u

HELPER="$(cd "$(dirname "$0")/.." && pwd)/docker/scripts/update_helper.sh"
FAILS=0

# write_status <dir> <state> <ts> [queue_pos]
write_status() {
    { echo "state=$2"; echo "ts=$3"; [ -n "${4:-}" ] && echo "queue_pos=$4"; } > "$1/.daemon-status"
}

# run_case <name> <expected: managed|fallback> <setup-fn> [expected-log-substring]
run_case() {
    local name="$1" expect="$2" setup="$3" expect_log="${4:-}"
    local tmp result
    tmp=$(mktemp -d)
    result=$(
        export EGG_DIR="$tmp/egg" GAME_CSGO_DIR="$tmp/csgo" LOG_OUT="$tmp/log"
        export DAEMON_STATUS_STALE_SECS=2 DAEMON_WAIT_MAX_SECS=2 DAEMON_WAIT_SECS=1
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
    if [ -n "$expect_log" ] && ! grep -q "$expect_log" "$tmp/log" 2>/dev/null; then
        ok=false
    fi
    if $ok; then
        echo "PASS  $name"
    else
        echo "FAIL  $name (got: $result, expected: $expect${expect_log:+, log must contain '$expect_log'})"
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

# --- run --------------------------------------------------------------------

run_case "done (this boot) -> managed"                managed  s_done_fresh
run_case "failed (this boot) -> instant fallback"     fallback s_failed_fresh "KL-DMN-03"
run_case "queued -> done flip -> managed"             managed  s_queued_then_done
run_case "no signal -> timeout fallback"              fallback s_no_signal
run_case "pre-boot done not accepted -> fallback"     fallback s_preboot_done_only
run_case "legacy marker -> managed + deprecation"     managed  s_legacy_marker "2026-10-01"
run_case "done but zero readable VPK -> fallback"     fallback s_done_no_vpk "KL-DMN-04"
run_case "stale queued (dead daemon) -> fallback"     fallback s_stale_queued

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
    echo "PASS  standalone steamapps -> fast fallback (${elapsed}s)"
else
    echo "FAIL  standalone steamapps -> fast fallback (result=$result, elapsed=${elapsed}s)"
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
    echo "PASS  broken VPK symlinks cleaned, valid ones kept"
else
    echo "FAIL  broken VPK symlinks cleaned, valid ones kept"
    FAILS=$((FAILS + 1))
fi
rm -rf "$tmp"

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo "All cases passed."
else
    echo "$FAILS case(s) FAILED."
    exit 1
fi
