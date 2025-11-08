#!/bin/bash
# Unified game update checker/runner

set -euo pipefail

source /utils/logging.sh
source /utils/config.sh
source /utils/version.sh

usage() {
  cat <<EOF
Usage: /scripts/check-updates.sh [--once|--loop]

Options:
  --once   Run a single update check (default). Uses a lock to avoid overlap.
  --loop   Run the continuous version check loop (respects AUTO_UPDATE and intervals).
  -h       Show this help.
EOF
}

MODE="once"
if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage; exit 0
fi
if [[ ${1:-} == "--loop" ]]; then
  MODE="loop"
fi

# Ensure configs are loaded when run outside entrypoint/cron env
init_egg_directories || true
load_configs || true

if [[ "$MODE" == "loop" ]]; then
  log_message "Starting version check loop" "info"
  version_check_loop
  exit 0
fi

# Single run with lock (atomic creation to avoid race condition)
LOCKFILE="/tmp/cs2_update_check.lock"
if ! { set -C; 2>/dev/null > "$LOCKFILE"; }; then
  log_message "Update check already running, skipping..." "debug"
  exit 0
fi

trap 'rm -f "$LOCKFILE"' EXIT

# Respect AUTO_UPDATE gating if present
if [ "${AUTO_UPDATE:-${UPDATE_AUTO_RESTART:-0}}" -ne 1 ]; then
  log_message "Auto update disabled, skipping check" "debug"
  exit 0
fi

check_for_new_updates || true
