#!/bin/bash
# KitsuneLab CS2 Centralized Update Script
# Automatically updates CS2 files and pushes them to all server containers
#
# Usage: ./update-cs2-centralized.sh [--simulate] [--validate]
#        ./update-cs2-centralized.sh --daemon
#        ./update-cs2-centralized.sh --test
#
#   --simulate    Skip SteamCMD update, simulate update and trigger restart logic
#   --validate    Force one-shot file validation (steamcmd validate) for this run
#                 only. Configured VALIDATE_INSTALL value is not touched.
#   --daemon      Run as event listener daemon - pushes game files instantly when
#                 a CS2 container starts (new server or restart). Install as a
#                 systemd service for automatic startup.
#   --test        Download the boot-handshake protocol test suite from GitHub
#                 (same branch as self-update), run it, clean up. No docker or
#                 config needed - quick sanity check for support/diagnostics.
#   --doctor      Health check of the whole setup: script/service/cron paths,
#                 daemon state, dependencies, per-server status files, locks.
#                 Applies safe fixes automatically, prints commands for the rest.
#
# Version: 1.0.52

set -euo pipefail

# ============================================================================
# CONFIGURATION - Edit these values for your setup
# ============================================================================

# Required: CS2 App ID (don't change unless you know what you're doing)
APP_ID="730"

# Required: Path where centralized CS2 files are stored
# This must match the path you configured in Pterodactyl mounts
CS2_DIR="/srv/cs2-shared"

# Required: SteamCMD installation directory
STEAMCMD_DIR="/root/steamcmd"

# Optional: Docker images for server detection (for automatic server restart)
# Servers using these images will be automatically restarted after update
# Supports multiple images separated by spaces or commas
# Examples:
#   Single: "sples1/k4ryuu-cs2"
#   Multiple: "sples1/k4ryuu-cs2 ghcr.io/k4ryuu/cs2-egg"
#   With commas: "sples1/k4ryuu-cs2,ghcr.io/k4ryuu/cs2-egg"
SERVER_IMAGE="sples1/k4ryuu-cs2 ghcr.io/k4ryuu/cs2-egg"

# Optional: Enable automatic server restart after update (true/false)
# Set to "false" if you want servers to sync on next manual restart
AUTO_RESTART_SERVERS="true"

# Optional: Validate game files integrity during update (true/false)
# Set to "false" for faster updates (recommended for cron)
# Set to "true" to verify all files (useful for troubleshooting)
VALIDATE_INSTALL="false"

# Optional: Enable automatic script self-update (true/false)
# Script checks GitHub for updates and auto-replaces itself
# Keeps last 3 versions as backup, validates before applying
AUTO_UPDATE_SCRIPT="true"

# Optional: Interval between update checks in seconds
# "*" = check every cron run (recommended with * * * * * cron)
# Number = minimum seconds between checks (e.g. 600 = at most once per 10 minutes)
UPDATE_CHECK_INTERVAL="*"

# Optional: Push updated game files directly into server volumes after each update
# This replaces the need for Pterodactyl/Pelican mount config + SYNC_LOCATION on the egg
# "symlink"  = symlinks to CS2_DIR, panel sees ~0 disk usage per server (default)
#              CS2_DIR is bind-mounted read-only into each container automatically
#              requires kernel 5.2+ (Ubuntu 20.04+), python3 on the host
# "hardlink" = hardlinks to CS2_DIR inodes, zero extra REAL disk space but panel
#              disk quota counts full size (~53GB) - use only if quota doesn't matter
#              falls back to copy if CS2_DIR and panel volumes are on different filesystems
# "copy"     = full copy per server, each server owns its files, writable
# "off"      = disable push, servers won't receive game files automatically
VPK_PUSH_METHOD="symlink"

# Optional: Max parallel file pushes in daemon mode (worker pool size)
# Symlink mounts are instant and not limited by this. Raise if you mass-create
# many servers at once and the host has disk/CPU headroom.
MAX_WORKERS="8"

# Optional: Path to the Wings config.yml (used for the auto-restart API call)
# Leave empty to auto-detect: /etc/pterodactyl/config.yml (Pterodactyl), then
# /etc/pelican/config.yml (Pelican). Set it only if Wings runs with a custom
# --config path.
WINGS_CONFIG=""

# ! ============================================================================
# ! DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# ! ============================================================================

# Simulate mode flag (set by --simulate argument)
SIMULATE_MODE=false

# Store original arguments for self-update restart
ORIGINAL_ARGS=("$@")

_DAEMON_WORKER_FD=   # fd for worker pool token bucket; set by run_event_daemon

# ============================================================================
# INTERNAL CONSTANTS
# ============================================================================

# Self-update configuration (internal)
GITHUB_REPO="K4ryuu/CS2-Egg"
GITHUB_BRANCH="main"
SCRIPT_FILENAME="update-cs2-centralized.sh"
REMOTE_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/misc/${SCRIPT_FILENAME}"

# Update tracking files
UPDATE_CHECK_TIMESTAMP_FILE="/var/cache/cs2-update-script-check"
UPDATE_BACKUP_DIR="$(dirname "$0")/.script-backups"
UPDATE_KEEP_BACKUPS=3

# Boot handshake status protocol (egg/.daemon-status in each volume, see
# docs/features/vpk-sync.md). Held exclusive by update_cs2 while steamcmd
# rewrites CS2_DIR; held shared by push workers during verify/push.
CENTRAL_UPDATE_LOCK="/var/lock/cs2-central-update.lock"
# Worker registry (tmpfs): one file per in-flight worker, consumed by the
# status refresher loop to keep waiting eggs' status files fresh.
DAEMON_REGISTRY_DIR="/run/cs2-vpk-daemon"
_REFRESHER_PID=

# ============================================================================
# STYLING / COLORS
# ============================================================================

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BOLD="\033[1m"; DIM="\033[2m"
    RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
    BLUE="\033[34m"; MAGENTA="\033[35m"; CYAN="\033[36m"
    RESET="\033[0m"
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; RESET=""
fi

format_bytes() {
    numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0} B"
}

log_info()    { echo -e "ℹ ${BOLD}${CYAN}INFO${RESET}  $*" >&2; }
log_ok()      { echo -e "✓ ${BOLD}${GREEN}DONE${RESET}  $*" >&2; }
log_warn()    { echo -e "⚠ ${BOLD}${YELLOW}WARN${RESET}  $*" >&2; }
log_error()   { echo -e "✗ ${BOLD}${RED}ERROR${RESET} $*" >&2; }
section()     { echo -e "\n${BOLD}${MAGENTA}==>${RESET} ${BOLD}$*${RESET}\n" >&2; }
headline()    {
    local title="$1"
    echo -e "${BOLD}${BLUE}──────────────────────────────────────────────────────${RESET}" >&2
    echo -e "${BOLD}${BLUE} ${title}${RESET}" >&2
    echo -e "${BOLD}${BLUE}──────────────────────────────────────────────────────${RESET}\n" >&2
}

# ============================================================================
# VALIDATION & SAFETY
# ============================================================================

validate_config() {
    local errors=0

    # Validate CS2_DIR path (must be absolute, no special chars except /-_)
    if [[ ! "$CS2_DIR" =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
        log_error "Invalid CS2_DIR path: $CS2_DIR"
        log_error "Path must be absolute and contain only alphanumeric, /, -, _ characters"
        errors=$((errors + 1))
    fi

    # Validate SteamCMD directory path
    if [[ ! "$STEAMCMD_DIR" =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
        log_error "Invalid STEAMCMD_DIR path: $STEAMCMD_DIR"
        log_error "Path must be absolute and contain only alphanumeric, /, -, _ characters"
        errors=$((errors + 1))
    fi

    # Validate APP_ID is numeric
    if [[ ! "$APP_ID" =~ ^[0-9]+$ ]]; then
        log_error "Invalid APP_ID: $APP_ID (must be numeric)"
        errors=$((errors + 1))
    fi

    # Validate MAX_WORKERS is a positive integer (0 would deadlock the worker pool)
    if [[ ! "$MAX_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Invalid MAX_WORKERS: $MAX_WORKERS (must be a positive number)"
        errors=$((errors + 1))
    fi

    # Validate Docker configuration if auto-restart or VPK push is enabled
    if [ "$AUTO_RESTART_SERVERS" = "true" ] || [ "$VPK_PUSH_METHOD" != "off" ]; then
        if [ -z "$SERVER_IMAGE" ]; then
            log_error "SERVER_IMAGE is required when AUTO_RESTART_SERVERS=true or VPK_PUSH_METHOD is enabled"
            errors=$((errors + 1))
        fi
    fi

    # Validate VPK_PUSH_METHOD value
    case "$VPK_PUSH_METHOD" in
        symlink|hardlink|copy|off) ;;
        *)
            log_error "Invalid VPK_PUSH_METHOD: $VPK_PUSH_METHOD (must be: symlink, hardlink, copy, off)"
            errors=$((errors + 1))
            ;;
    esac

    if [ $errors -gt 0 ]; then
        log_error "Configuration validation failed with $errors error(s)"
        exit 1
    fi

    log_ok "Configuration validated successfully"
}

acquire_lock() {
    local lockfile="/var/lock/cs2-update.lock"

    # Create lock directory if it doesn't exist
    mkdir -p "$(dirname "$lockfile")" 2>/dev/null || true

    # Try to acquire lock
    exec 200>"$lockfile"
    if ! flock -n 200; then
        log_error "Another CS2 update instance is already running"
        log_info "Likely cause: Cron job is currently executing (runs every 1-2 minutes)"
        log_info "This is normal behavior during updates. Only remove lock if truly stuck: $lockfile"
        exit 1
    fi

    log_ok "Acquired update lock"
}

release_lock() {
    local lockfile="/var/lock/cs2-update.lock"
    flock -u 200 2>/dev/null || true
    rm -f "$lockfile" 2>/dev/null || true
}

# ============================================================================
# LIVE OUTPUT UTILITIES
# ============================================================================

# Friendly context for known SteamCMD failure codes found in a log file
_steamcmd_error_hint() {
    local error_code
    error_code=$(grep -oP "state is \K0x[0-9a-fA-F]+" "$1" 2>/dev/null | head -n1)
    [ -z "$error_code" ] && return 0
    echo "" >&2
    if [ "$error_code" = "0x202" ]; then
        log_error "SteamCMD Error 0x202 - Disk space or filesystem issue"
        log_info "CS2 requires ~60GB for initial installation"
        log_info "Free up disk space and retry. Check: ${BOLD}df -h $(dirname "$CS2_DIR")${RESET}"
    else
        log_error "SteamCMD Error $error_code detected - review output above"
    fi
}

run_with_spinner() {
    local label="$1"; shift
    local cmd=("$@")
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local start_ts=$(date +%s)
    local log_file="/tmp/cs2-update.$$.$RANDOM.log"

    "${cmd[@]}" >"$log_file" 2>&1 &
    local pid=$!

    printf "${BOLD}${MAGENTA}%s${RESET}\n" "$label" >&2
    while kill -0 $pid 2>/dev/null; do
        printf "\r${CYAN}%s${RESET} ${DIM}%s${RESET}" "${spin[$i]}" "$label" >&2
        i=$(((i+1)%${#spin[@]}))
        sleep 0.12
    done

    wait $pid
    local ec=$?
    local end_ts=$(date +%s)
    local dur=$((end_ts-start_ts))

    printf "\r" >&2

    if [ $ec -eq 0 ]; then
        log_ok "${label} finished in ${dur}s"
    else
        log_error "${label} failed after ${dur}s (exit $ec)"
        echo "${BOLD}Last 20 lines:${RESET}" >&2
        tail -n 20 "$log_file" >&2 || true
        _steamcmd_error_hint "$log_file"
        rm -f "$log_file"
        return $ec
    fi

    rm -f "$log_file"
    return 0
}

ensure_steamcmd_dependencies() {
    # Check and add i386 architecture (required for 32-bit SteamCMD)
    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
        log_info "Adding i386 architecture..."
        local arch_error
        arch_error=$(dpkg --add-architecture i386 2>&1) || {
            log_error "Failed to add i386 architecture"
            echo "$arch_error" | tail -n 5 >&2
            exit 1
        }

        local update_error
        update_error=$(apt-get update -qq 2>&1) || {
            log_error "Failed to update package lists after adding i386 architecture"
            echo "$update_error" | tail -n 5 >&2
            exit 1
        }
    fi

    # Check for required 32-bit libraries (lib32gcc-s1 on newer systems, lib32gcc1 on older)
    if ! dpkg -l lib32gcc-s1 2>/dev/null | grep -q "^ii" && \
       ! dpkg -l lib32gcc1 2>/dev/null | grep -q "^ii"; then

        # Try modern package first (Ubuntu 20.04+, Debian 11+)
        if run_with_spinner "Installing 32-bit libraries (modern)" \
            env DEBIAN_FRONTEND=noninteractive apt-get install -y -q lib32gcc-s1 lib32stdc++6; then
            : # Success
        # Fallback to legacy package (Ubuntu 18.04, Debian 10)
        elif run_with_spinner "Installing 32-bit libraries (legacy)" \
            env DEBIAN_FRONTEND=noninteractive apt-get install -y -q lib32gcc1 lib32stdc++6; then
            : # Success
        else
            log_error "Failed to install 32-bit libraries (tried both lib32gcc-s1 and lib32gcc1)"
            exit 1
        fi
    fi

    return 0
}

install_or_reinstall_steamcmd() {
    section "SteamCMD Setup"

    # Health check - verify all prerequisites
    local needs_deps=false
    local needs_install=false

    # Check i386 architecture
    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
        needs_deps=true
    fi

    # Check 32-bit libraries (lib32gcc-s1 on newer systems, lib32gcc1 on older)
    if ! dpkg -l lib32gcc-s1 2>/dev/null | grep -q "^ii" && \
       ! dpkg -l lib32gcc1 2>/dev/null | grep -q "^ii"; then
        needs_deps=true
    fi

    # Check SteamCMD installation
    if [ ! -f "$STEAMCMD_DIR/steamcmd.sh" ] || [ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]; then
        needs_install=true
    elif [ ! -f "$STEAMCMD_DIR/linux32/steamclient.so" ] && [ ! -f "$STEAMCMD_DIR/linux64/steamclient.so" ]; then
        needs_install=true
    fi

    # If everything is OK, we're done
    if [ "$needs_deps" = false ] && [ "$needs_install" = false ]; then
        log_ok "SteamCMD health check passed"
        return 0
    fi

    # Install dependencies if needed
    if [ "$needs_deps" = true ]; then
        ensure_steamcmd_dependencies || exit 1
    fi

    # Install SteamCMD if needed
    if [ "$needs_install" = true ]; then
        log_info "Installing SteamCMD..."
        rm -rf "$STEAMCMD_DIR"
        mkdir -p "$STEAMCMD_DIR"

        local download_error
        download_error=$(curl -sqL 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz' 2>&1 | tar -xz -C "$STEAMCMD_DIR" 2>&1) || {
            log_error "Failed to download/extract SteamCMD"
            echo "$download_error" | tail -n 5 >&2
            exit 1
        }

        # Validate extraction
        if [ ! -f "$STEAMCMD_DIR/steamcmd.sh" ]; then
            log_error "SteamCMD extraction validation failed (steamcmd.sh not found)"
            exit 1
        fi

        chmod +x "$STEAMCMD_DIR/steamcmd.sh"
        log_ok "SteamCMD installed at $STEAMCMD_DIR"
    fi
}

get_local_version() {
    # Read buildid from SteamCMD appmanifest
    local manifest="$CS2_DIR/steamapps/appmanifest_$APP_ID.acf"
    if [ -f "$manifest" ]; then
        grep -Po '^\s*"buildid"\s*"\K[^"]+' "$manifest" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

update_cs2() {
    section "CS2 Update"

    local version_before=$(get_local_version)
    mkdir -p "$CS2_DIR"

    # Block push workers while steamcmd rewrites CS2_DIR: workers hold this lock
    # shared during verify/push, so neither side ever sees a half-written tree.
    # A restarting server meanwhile shows "central update in progress" and waits.
    touch "$CENTRAL_UPDATE_LOCK" 2>/dev/null || true
    exec 201>"$CENTRAL_UPDATE_LOCK"
    if ! flock -x -w 3600 201; then
        log_error "Central update lock busy for 1h - a push worker may be stuck; skipping update this run"
        exec 201>&-
        return 1
    fi

    # Build validate flag based on configuration
    local validate_flag=""
    if [ "$VALIDATE_INSTALL" = "true" ]; then
        validate_flag="validate"
    fi

    if ! run_with_spinner "Checking for updates and downloading" \
        "$STEAMCMD_DIR/steamcmd.sh" +force_install_dir "$CS2_DIR" +login anonymous +app_update "$APP_ID" $validate_flag +quit; then
        log_error "CS2 update failed"
        exit 1
    fi

    local version_after=$(get_local_version)

    if [ "$version_before" = "$version_after" ]; then
        log_ok "CS2 is already up to date (version: $version_after)"
    else
        if [ "$version_before" = "unknown" ]; then
            log_ok "CS2 installed successfully (version: ${BOLD}$version_after${RESET})"
        else
            log_ok "CS2 updated successfully: $version_before → ${BOLD}$version_after${RESET}"
        fi
    fi

    # Install Steam client libraries
    mkdir -p "$CS2_DIR/.steam/sdk32" "$CS2_DIR/.steam/sdk64"
    cp -f "$STEAMCMD_DIR/linux32/steamclient.so" "$CS2_DIR/.steam/sdk32/" 2>/dev/null || true
    cp -f "$STEAMCMD_DIR/linux64/steamclient.so" "$CS2_DIR/.steam/sdk64/" 2>/dev/null || true

    # Set permissions: dirs 755, files keep their exec bit (cs2.sh, binaries)
    # instead of a blanket 755 that marked every game file executable
    chown -R pterodactyl:pterodactyl "$CS2_DIR" 2>/dev/null || true
    chmod -R u=rwX,go=rX "$CS2_DIR"

    # CS2_DIR consistent again - let waiting push workers proceed
    exec 201>&-

    local size=$(du -sh "$CS2_DIR" 2>/dev/null | cut -f1)
    log_info "CS2 directory size: ${BOLD}$size${RESET}"

    # Return 0 if update happened, 1 if already up to date
    [ "$version_before" != "$version_after" ]
}

# Path of the Wings config.yml, empty if none is readable.
# Pelican ships the same Wings config schema, just under /etc/pelican.
WINGS_CONFIG_PATHS=(/etc/pterodactyl/config.yml /etc/pelican/config.yml)

get_wings_config() {
    if [ -n "$WINGS_CONFIG" ]; then
        [ -r "$WINGS_CONFIG" ] && echo "$WINGS_CONFIG"
        return 0
    fi

    local cfg
    for cfg in "${WINGS_CONFIG_PATHS[@]}"; do
        if [ -r "$cfg" ]; then
            echo "$cfg"
            return 0
        fi
    done

    return 0
}

get_wings_token() {
    local config="$1"

    local token=$(grep -E '^\s*token:' "$config" | head -1 | awk '{print $2}' | tr -d '"' || true)

    if [ -z "$token" ]; then
        return 1
    fi

    echo "$token"
}

get_wings_api_url() {
    local config="$1"

    # Extract API configuration from config.yml api section
    local api_section=$(sed -n '/^api:/,/^[a-z]/p' "$config")

    # Get host and port from api section
    local host=$(echo "$api_section" | grep -E '^\s+host:' | head -1 | awk '{print $2}' | tr -d '"' || echo "0.0.0.0")
    local port=$(echo "$api_section" | grep -E '^\s+port:' | head -1 | awk '{print $2}' | tr -d '"' || echo "8080")

    # Get SSL enabled status from api.ssl section
    local ssl_section=$(echo "$api_section" | sed -n '/^\s\+ssl:/,/^\s\+[a-z]/p')
    local ssl_enabled=$(echo "$ssl_section" | grep -E '^\s+enabled:' | head -1 | awk '{print $2}' | tr -d '"' || echo "true")

    # If host is 0.0.0.0, use 127.0.0.1 for localhost
    if [ "$host" = "0.0.0.0" ]; then
        host="127.0.0.1"
    fi

    # Determine protocol based on SSL setting
    local protocol="https"
    if [ "$ssl_enabled" = "false" ]; then
        protocol="http"
    fi

    echo "${protocol}://${host}:${port}"
}

# Print names of running containers using any configured SERVER_IMAGE, one per line
_matching_containers() {
    local images="${SERVER_IMAGE//,/ }"
    local grep_pattern="" img escaped_img
    for img in $images; do
        escaped_img=$(printf '%s' "$img" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
        [ -z "$grep_pattern" ] && grep_pattern="$escaped_img" || grep_pattern="$grep_pattern|$escaped_img"
    done
    # || true: no match must not kill the script under pipefail + set -e
    docker ps --format "{{.Names}}\t{{.Image}}" | grep -E "$grep_pattern" | cut -f1 || true
}

# Host path of a container's /home/container volume
_volume_path() {
    docker inspect "$1" \
        --format '{{range .Mounts}}{{if eq .Destination "/home/container"}}{{.Source}}{{end}}{{end}}' \
        2>/dev/null
}

restart_docker_containers() {
    section "Detecting and Restarting Servers"

    local -a container_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && container_array+=("$line")
    done < <(_matching_containers)

    if [ ${#container_array[@]} -eq 0 ]; then
        log_info "No containers found using images: ${BOLD}${SERVER_IMAGE//,/ }${RESET}"
        return 0
    fi

    local count=${#container_array[@]}
    log_info "Found ${BOLD}$count${RESET} container(s) using images: ${BOLD}${SERVER_IMAGE//,/ }${RESET}"

    # List containers for visibility
    for c in "${container_array[@]}"; do
        echo -e "  ${DIM}→ $c${RESET}" >&2
    done

    # Get Wings API credentials
    local config
    local token
    local api_url

    config=$(get_wings_config)

    if [ -z "$config" ]; then
        log_error "Wings config not found - cannot restart servers"
        log_error "Looked for: ${WINGS_CONFIG_PATHS[*]}"
        log_error "Wings elsewhere? Set WINGS_CONFIG in this script. Also make sure this script runs as root, config.yml is only readable by root"
        return 1
    fi

    if ! token=$(get_wings_token "$config") || ! api_url=$(get_wings_api_url "$config"); then
        log_error "Wings API not available - cannot restart servers"
        log_error "No API token found in $config"
        return 1
    fi

    log_info "Using Wings API for restart (${DIM}$config${RESET})"

    local success=0
    local failed=0

    for container in "${container_array[@]}"; do
        # Container name IS the UUID in Pterodactyl
        local uuid="$container"

        # Wings API restart
        local response
        local http_code

        if ! response=$(curl -k -s -w "\n%{http_code}" \
            --connect-timeout 10 --max-time 30 \
            -X POST "${api_url}/api/servers/${uuid}/power" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d '{"action":"restart"}' \
            2>/dev/null); then
            # real newline so tail -n1 yields a clean http code on curl failure
            response=$'error\n000'
        fi

        http_code=$(echo "$response" | tail -n1)

        if [ "$http_code" = "202" ] || [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
            log_ok "Restarted ${BOLD}$container${RESET} via Wings API"
            ((success++)) || true
        else
            log_warn "Failed to restart ${BOLD}$container${RESET} via Wings API (HTTP $http_code)"
            ((failed++)) || true
        fi
    done

    if [ $failed -gt 0 ]; then
        log_warn "Restarted $success/$count container(s) successfully ($failed failed)"
        return 1
    else
        log_ok "All containers restarted successfully (${BOLD}$success/$count${RESET})"
        return 0
    fi
}

# ============================================================================
# STATUS FILE PROTOCOL (boot handshake with the egg)
# ============================================================================
# One read-only file per volume: egg/.daemon-status with state=/ts=/queue_pos=
# lines. The egg never deletes it - it accepts "done"/"failed" only when ts is
# newer than its own boot, and keeps waiting on any non-terminal state while
# ts stays fresh (refreshed every 3s). Stale ts = dead daemon = SteamCMD
# fallback. Writes are atomic (tmp + mv) and serialized per container via
# flock, so a refresher tick can never resurrect an already-terminal state.

# Unconditional status write. Usage: _write_status container volume state [queue_pos]
_write_status() {
    local container="$1" volume="$2" state="$3" qpos="${4:-}"
    local dir="$volume/egg"
    mkdir -p "$dir" 2>/dev/null || return 0
    (
        exec 9>"/var/lock/cs2-vpk-status-${container}.lock"
        flock -w 5 9 || exit 0
        local tmp
        tmp=$(mktemp "$dir/.daemon-status.XXXXXX" 2>/dev/null) || exit 0
        {
            echo "state=$state"
            echo "ts=$(date +%s)"
            [ -n "$qpos" ] && echo "queue_pos=$qpos"
        } > "$tmp" 2>/dev/null
        chown pterodactyl:pterodactyl "$tmp" 2>/dev/null || true
        chmod 644 "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$dir/.daemon-status" 2>/dev/null || rm -f "$tmp" 2>/dev/null
        exit 0
    ) || true
    return 0
}

# Bump ts on a non-terminal status so the waiting egg knows we're alive.
# Never touches done/failed - the state is re-read under the same lock that
# terminal writes take, so no tick can overwrite a just-written terminal state.
_refresh_status_entry() {
    local container="$1" volume="$2" qpos="${3:-}"
    local file="$volume/egg/.daemon-status"
    (
        exec 9>"/var/lock/cs2-vpk-status-${container}.lock"
        flock -w 5 9 || exit 0
        local state
        state=$(grep -m1 '^state=' "$file" 2>/dev/null | cut -d= -f2 || true)
        case "$state" in
            queued|updating|verifying|pushing) ;;
            *) exit 0 ;;
        esac
        if [ -z "$qpos" ] && [ "$state" = "queued" ]; then
            qpos=$(grep -m1 '^queue_pos=' "$file" 2>/dev/null | cut -d= -f2 || true)
        fi
        local tmp
        tmp=$(mktemp "$volume/egg/.daemon-status.XXXXXX" 2>/dev/null) || exit 0
        {
            echo "state=$state"
            echo "ts=$(date +%s)"
            [ -n "$qpos" ] && echo "queue_pos=$qpos"
        } > "$tmp" 2>/dev/null
        chown pterodactyl:pterodactyl "$tmp" 2>/dev/null || true
        chmod 644 "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
        exit 0
    ) || true
    return 0
}

# Flip a still-pending status to failed (worker died without a terminal write),
# so the egg falls back to SteamCMD immediately instead of waiting out staleness.
_fail_status_if_pending() {
    local container="$1" volume="$2"
    (
        exec 9>"/var/lock/cs2-vpk-status-${container}.lock"
        flock -w 5 9 || exit 0
        local state
        state=$(grep -m1 '^state=' "$volume/egg/.daemon-status" 2>/dev/null | cut -d= -f2 || true)
        case "$state" in
            queued|updating|verifying|pushing) ;;
            *) exit 0 ;;
        esac
        exit 1
    ) && return 0
    _write_status "$container" "$volume" "failed"
    return 0
}

# Daemon-side refresher: single loop, one tick every 3s. Refreshes ts for every
# registered in-flight worker, recomputes queue positions, and flips the status
# of crashed workers to failed. Does nothing slow, cannot back up.
_status_refresher() {
    set +e
    local reg container pid volume enq state pos
    while sleep 3; do
        [ -d "$DAEMON_REGISTRY_DIR" ] || continue
        local -a queued_list=()
        for reg in "$DAEMON_REGISTRY_DIR"/*; do
            [ -e "$reg" ] || continue
            container=${reg##*/}
            pid=$(grep -m1 '^pid=' "$reg" 2>/dev/null | cut -d= -f2)
            volume=$(grep -m1 '^volume=' "$reg" 2>/dev/null | cut -d= -f2)
            enq=$(grep -m1 '^enq=' "$reg" 2>/dev/null | cut -d= -f2)
            [ -z "$volume" ] && { rm -f "$reg"; continue; }
            if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                _fail_status_if_pending "$container" "$volume"
                rm -f "$reg"
                continue
            fi
            state=$(grep -m1 '^state=' "$volume/egg/.daemon-status" 2>/dev/null | cut -d= -f2)
            if [ "$state" = "queued" ]; then
                queued_list+=("${enq:-0} $container $volume")
            else
                _refresh_status_entry "$container" "$volume"
            fi
        done
        pos=1
        while read -r enq container volume; do
            [ -z "$container" ] && continue
            _refresh_status_entry "$container" "$volume" "$pos"
            pos=$((pos + 1))
        done < <(printf '%s\n' "${queued_list[@]:-}" | sort -n)
    done
}

# ============================================================================
# VPK PUSH FUNCTIONS
# ============================================================================

# Bind-mount CS2_DIR into a running container's mount namespace via nsenter.
# Called on every 'start' event - the container is alive but entrypoint hasn't
# checked for VPKs yet (sleep 1 + init gives us a comfortable window).
_nsenter_mount() {
    local container="$1"
    local src="$2"
    local dst="$3"

    local pid
    pid=$(docker inspect --format '{{.State.Pid}}' "$container" 2>/dev/null) || {
        log_warn "nsenter[$container]: docker inspect failed"
        return 1
    }
    if [ "${pid:-0}" = "0" ]; then
        log_warn "nsenter[$container]: PID=0, container not running yet"
        return 1
    fi
    log_info "nsenter[$container]: pid=$pid src=$src dst=$dst"

    # src must exist and be readable on host
    if [ ! -d "$src" ]; then
        log_warn "nsenter[$container]: src $src does not exist on host"
        return 1
    fi
    log_info "nsenter[$container]: src ok ($(ls "$src" 2>/dev/null | wc -l) entries, perms: $(stat -c '%a %U:%G' "$src" 2>/dev/null))"

    # Check if already mounted by reading the container's mount table from the host.
    # /proc/$pid/mountinfo field 5 is the mount point path - no nsenter needed, no hang risk.
    if awk -v dst="$dst" '$5 == dst {found=1} END {exit !found}' "/proc/$pid/mountinfo" 2>/dev/null; then
        log_info "nsenter[$container]: $dst already mounted, skipping"
        return 0
    fi
    log_info "nsenter[$container]: not yet mounted, proceeding"

    # open_tree() + move_mount() approach (kernel 5.2+, syscalls 428/429):
    # open_tree() creates a detached mount clone from the HOST namespace - it is not
    # bound to any mount namespace, so the kernel's check_mnt() cross-namespace check
    # does not apply. move_mount() then attaches it into the container's namespace.
    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "nsenter[$container]: python3 not found on host - cannot bind-mount into container"
        log_warn "nsenter[$container]: install with: apt-get install -y python3"
        return 1
    fi

    local mount_err
    if ! mount_err=$(NSENTER_PID="$pid" NSENTER_SRC="$src" NSENTER_DST="$dst" \
        timeout 15 python3 - 2>&1 <<'PYEOF'
import os, ctypes, sys, fcntl
try:
    pid    = int(os.environ['NSENTER_PID'])
    src    = os.environ['NSENTER_SRC'].encode()
    dst    = os.environ['NSENTER_DST'].encode()
    libc   = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    mnt_fd = os.open(f'/proc/{pid}/ns/mnt', os.O_RDONLY)
    fcntl.fcntl(mnt_fd, fcntl.F_SETFD, 0)
    # open_tree(AT_FDCWD, src, OPEN_TREE_CLONE) from HOST namespace
    # returns a detached mount fd not tied to any namespace
    tree_fd = int(libc.syscall(ctypes.c_long(428), ctypes.c_int(-100),
                               ctypes.c_char_p(src), ctypes.c_uint(1)))
    if tree_fd < 0:
        sys.stderr.write(f'open_tree: {os.strerror(ctypes.get_errno())}\n'); sys.exit(1)
    fcntl.fcntl(tree_fd, fcntl.F_SETFD, 0)
except Exception as e:
    sys.stderr.write(f'setup: {e}\n'); sys.exit(1)
child = os.fork()
if child == 0:
    if libc.setns(ctypes.c_int(mnt_fd), ctypes.c_int(0)) != 0:
        sys.stderr.write(f'setns: {os.strerror(ctypes.get_errno())}\n'); os._exit(2)
    os.makedirs(dst.decode(), exist_ok=True)
    # move_mount(tree_fd, "", AT_FDCWD, dst, MOVE_MOUNT_F_EMPTY_PATH=4)
    # attaches the detached mount into the container's namespace - no check_mnt() block
    r = int(libc.syscall(ctypes.c_long(429), ctypes.c_int(tree_fd), ctypes.c_char_p(b''),
                         ctypes.c_int(-100), ctypes.c_char_p(dst), ctypes.c_uint(4)))
    if r != 0:
        sys.stderr.write(f'move_mount: {os.strerror(ctypes.get_errno())}\n'); os._exit(1)
    libc.mount(b'none', dst, b'none', ctypes.c_ulong(4096|32|1), None)  # remount ro
    os._exit(0)
_, st = os.waitpid(child, 0); sys.exit(os.WEXITSTATUS(st))
PYEOF
    ); then
        log_warn "nsenter[$container]: mount failed: $mount_err"
        return 1
    fi
    log_info "nsenter[$container]: bind mount ok"
}

# Sync base files + VPK files from CS2_DIR into a single server volume.
# Wrapper owns the push lifecycle signals: status file pushing -> done/failed,
# plus the legacy .daemon-push-active heartbeat for pre-status-file eggs
# (! TODO: remove the legacy heartbeat after 2026-10-01, eggs < status protocol).
# Both are refreshed every 3s while the push runs; a crashed pusher stops the
# heartbeat, so a waiting egg falls back instead of waiting forever.
# Works from both the daemon workers and the cron push path.
_sync_to_volume() {
    local _hb_file="$2/egg/.daemon-push-active"
    local _owner=$BASHPID
    mkdir -p "$2/egg" 2>/dev/null
    touch "$_hb_file" 2>/dev/null || true
    _write_status "$1" "$2" "pushing"
    ( while sleep 3; do
          kill -0 "$_owner" 2>/dev/null || exit
          touch "$_hb_file" 2>/dev/null || true
          _refresh_status_entry "$1" "$2"
      done ) &
    local _hb_pid=$!

    local rc=0
    _sync_to_volume_impl "$@" || rc=$?

    kill "$_hb_pid" 2>/dev/null || true
    rm -f "$_hb_file" 2>/dev/null || true
    if [ $rc -eq 0 ]; then
        _write_status "$1" "$2" "done"
    else
        _write_status "$1" "$2" "failed"
    fi
    return $rc
}

_sync_to_volume_impl() {
    local container="$1"
    local dest="$2"
    local src="$CS2_DIR"

    local container_mount_dst="/tmp/cs2-shared"

    # marker is touched at the END of push (last-touch design)
    mkdir -p "$dest/egg" 2>/dev/null
    chown -R pterodactyl:pterodactyl "$dest/egg" 2>/dev/null || true

    # Sync non-VPK base files; exclude per-server configs, gameinfo.gi, and
    # SteamCMD-only dirs (Steam/, steamapps/): the CS2 server doesn't need them at
    # runtime, and the container-side cleanup would just delete them each boot.
    # --no-o --no-g: don't overwrite ownership (preserve volume root owner = pterodactyl)
    rsync -aK --no-o --no-g \
        --exclude '*.vpk' \
        --exclude 'cfg/' \
        --exclude 'game/csgo/gameinfo.gi' \
        --exclude 'Steam/' \
        --exclude 'steamapps/' \
        "$src/" "$dest" 2>/dev/null || {
        log_warn "rsync failed for $container"
        return 1
    }

    # Ensure volume root stays writable for the container user
    chmod 755 "$dest" 2>/dev/null || true

    # Copy gameinfo.gi only on first sync - don't overwrite the server's own
    local gameinfo_src="$src/game/csgo/gameinfo.gi"
    local gameinfo_dst="$dest/game/csgo/gameinfo.gi"
    if [ -f "$gameinfo_src" ] && [ ! -f "$gameinfo_dst" ]; then
        cp "$gameinfo_src" "$gameinfo_dst" 2>/dev/null || true
    fi

    # Copy cfg files - only if they don't already exist (never overwrite)
    local cfg_src="$src/game/csgo/cfg"
    local cfg_dst="$dest/game/csgo/cfg"
    if [ -d "$cfg_src" ]; then
        mkdir -p "$cfg_dst" 2>/dev/null || true
        while IFS= read -r -d '' cfg_file; do
            local rel="${cfg_file#$cfg_src/}"
            local dst_file="$cfg_dst/$rel"
            if [ ! -e "$dst_file" ]; then
                mkdir -p "$(dirname "$dst_file")" 2>/dev/null || true
                cp "$cfg_file" "$dst_file" 2>/dev/null || true
            fi
        done < <(find "$cfg_src" -type f \( -name "*.cfg" -o -name "*.vcfg" \) -print0 2>/dev/null)
    fi

    # Handle VPK files
    local vpk_count=0
    local vpk_size=0

    while IFS= read -r -d '' vpk_file; do
        local rel="${vpk_file#$src/}"
        local link_dst="$dest/$rel"

        mkdir -p "$(dirname "$link_dst")" 2>/dev/null

        local fsize
        fsize=$(stat -c %s "$vpk_file" 2>/dev/null || echo 0)
        [[ "$fsize" =~ ^[0-9]+$ ]] || fsize=0

        # Remove existing file/link before placing new one
        case "$VPK_PUSH_METHOD" in
            symlink)
                local target="${container_mount_dst}/${rel}"
                # skip if symlink already points to correct target
                if [ "$(readlink "$link_dst" 2>/dev/null)" = "$target" ]; then
                    ((vpk_count++)) || true
                    vpk_size=$((vpk_size + fsize))
                    continue
                fi
                { [ -e "$link_dst" ] || [ -L "$link_dst" ]; } && rm -f "$link_dst" 2>/dev/null
                ln -sf "$target" "$link_dst" 2>/dev/null || return 1
                ;;
            hardlink)
                local src_ino src_dev dst_dev
                src_ino=$(stat -c %i "$vpk_file" 2>/dev/null || echo 0)
                src_dev=$(stat -c %d "$vpk_file" 2>/dev/null || echo 0)
                # skip if already hardlinked to same inode; remove broken symlinks too
                if [ -e "$link_dst" ] || [ -L "$link_dst" ]; then
                    local dst_ino
                    dst_ino=$(stat -c %i "$link_dst" 2>/dev/null || echo 1)
                    if [ "$src_ino" = "$dst_ino" ]; then
                        ((vpk_count++)) || true
                        vpk_size=$((vpk_size + fsize))
                        continue
                    fi
                    rm -f "$link_dst" 2>/dev/null
                fi
                dst_dev=$(stat -c %d "$(dirname "$link_dst")" 2>/dev/null || echo 1)
                local op_err
                if [ "$src_dev" != "$dst_dev" ]; then
                    # cross-filesystem: fall back to copy (one-time cost, rsync handles updates)
                    if ! op_err=$(cp "$vpk_file" "$link_dst" 2>&1); then
                        log_warn "hardlink[$container]: copy failed for $rel: $op_err"
                        return 1
                    fi
                    chown pterodactyl:pterodactyl "$link_dst" 2>/dev/null || true
                    chmod 644 "$link_dst" 2>/dev/null || true
                else
                    if ! op_err=$(ln "$vpk_file" "$link_dst" 2>&1); then
                        log_warn "hardlink[$container]: ln failed for $rel: $op_err"
                        return 1
                    fi
                fi
                ;;
            copy)
                cp "$vpk_file" "$link_dst" 2>/dev/null || return 1
                chown pterodactyl:pterodactyl "$link_dst" 2>/dev/null || true
                chmod 644 "$link_dst" 2>/dev/null || true
                ;;
        esac

        ((vpk_count++)) || true
        vpk_size=$((vpk_size + fsize))
    done < <(find "$src" -type f -name "*.vpk" -print0 2>/dev/null)

    local human_size
    human_size=$(format_bytes "$vpk_size")
    log_info "  ${DIM}→ $container: $vpk_count VPK(s), ${human_size}${RESET}"

    chown -R pterodactyl:pterodactyl "$dest/game" 2>/dev/null || true

    # push done: touch marker (signals "daemon alive + files ready")
    # symlink mode: marker is touched on start event after nsenter mount, not here
    # ! TODO: Remove after 2026-10-01 (legacy marker for pre-status-file eggs)
    if [ "$VPK_PUSH_METHOD" != "symlink" ]; then
        touch "$dest/egg/.daemon-managed" 2>/dev/null || true
        chown pterodactyl:pterodactyl "$dest/egg/.daemon-managed" 2>/dev/null || true
    fi

    return 0
}

# Verify every VPK present in CS2_DIR is properly placed on a server volume.
# Returns 0 if all VPKs look good, 1 if any is missing/broken.
# Self-heal trigger: caller should re-push when this returns non-zero.
_verify_volume_vpks() {
    local volume_path="$1"
    local container_mount_dst="/tmp/cs2-shared"

    [ "$VPK_PUSH_METHOD" = "off" ] && return 0

    while IFS= read -r -d '' src_file; do
        local rel="${src_file#$CS2_DIR/}"
        local vol_file="$volume_path/$rel"

        case "$VPK_PUSH_METHOD" in
            symlink)
                # must be a symlink pointing at the in-container mount path
                local expected="${container_mount_dst}/${rel}"
                [ -L "$vol_file" ] || return 1
                [ "$(readlink "$vol_file" 2>/dev/null)" = "$expected" ] || return 1
                ;;
            hardlink|copy)
                # size alone can miss an update that changed content but not size
                [ -f "$vol_file" ] || return 1
                local src_size dst_size
                src_size=$(stat -c %s "$src_file" 2>/dev/null || echo 0)
                dst_size=$(stat -c %s "$vol_file" 2>/dev/null || echo 0)
                [ "$src_size" = "$dst_size" ] || return 1
                local src_dev dst_dev
                src_dev=$(stat -c %d "$src_file" 2>/dev/null || echo 0)
                dst_dev=$(stat -c %d "$vol_file" 2>/dev/null || echo 1)
                if [ "$VPK_PUSH_METHOD" = "hardlink" ] && [ "$src_dev" = "$dst_dev" ]; then
                    # same fs: a proper hardlink shares the inode, exact check
                    [ "$(stat -c %i "$src_file" 2>/dev/null)" = "$(stat -c %i "$vol_file" 2>/dev/null)" ] || return 1
                else
                    # copy (or hardlink's cross-fs copy fallback): the copy was made
                    # after the source's last modification, so dst mtime >= src mtime
                    # means current; an updated source flips this and triggers re-push
                    local src_mtime dst_mtime
                    src_mtime=$(stat -c %Y "$src_file" 2>/dev/null || echo 0)
                    dst_mtime=$(stat -c %Y "$vol_file" 2>/dev/null || echo 0)
                    [ "$dst_mtime" -ge "$src_mtime" ] || return 1
                fi
                ;;
        esac
    done < <(find "$CS2_DIR" -type f -name "*.vpk" -print0 2>/dev/null)

    return 0
}

push_vpk_to_containers() {
    [ "$VPK_PUSH_METHOD" = "off" ] && return 0

    section "Pushing Game Files to Server Volumes"

    # symlink mode: ensure CS2_DIR is world-readable so container user can access the mount
    if [ "$VPK_PUSH_METHOD" = "symlink" ]; then
        chmod -R a+rX "$CS2_DIR" 2>/dev/null || true
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required for VPK push but not installed"
        return 1
    fi

    local -a container_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && container_array+=("$line")
    done < <(_matching_containers)

    if [ ${#container_array[@]} -eq 0 ]; then
        log_info "No running containers found for VPK push"
        return 0
    fi

    log_info "Pushing game files to ${BOLD}${#container_array[@]}${RESET} container(s) [method: ${BOLD}$VPK_PUSH_METHOD${RESET}]"

    local success=0
    local failed=0

    for container in "${container_array[@]}"; do
        local volume_path
        volume_path=$(_volume_path "$container")

        if [ -z "$volume_path" ] || [ ! -d "$volume_path" ]; then
            log_warn "Could not get volume path for $container, skipping"
            ((failed++)) || true
            continue
        fi

        # Same per-container mutex as the daemon workers, so a cron push and a
        # daemon self-heal never write the same volume concurrently.
        local lock_file="/var/lock/cs2-vpk-push-${container}.lock"
        local waited=0 got_lock=true
        while ! mkdir "$lock_file" 2>/dev/null; do
            if [ "$waited" -ge 120 ]; then got_lock=false; break; fi
            sleep 2
            waited=$((waited + 2))
        done
        if ! $got_lock; then
            log_warn "Push lock busy for ${BOLD}$container${RESET} after ${waited}s, skipping"
            ((failed++)) || true
            continue
        fi

        if _sync_to_volume "$container" "$volume_path"; then
            ((success++)) || true
        else
            log_warn "Push failed for ${BOLD}$container${RESET}"
            ((failed++)) || true
        fi
        rmdir "$lock_file" 2>/dev/null || true
    done

    # Hardlink mode: set VPK files in CS2_DIR to root:root 644
    # Hardlinks share the inode, so this makes them read-only for the container user too
    if [ "$VPK_PUSH_METHOD" = "hardlink" ] && [ $success -gt 0 ]; then
        find "$CS2_DIR" -type f -name "*.vpk" \
            -exec chown root:root {} + \
            -exec chmod 644 {} + 2>/dev/null || true
        log_info "VPK files set to read-only (hardlink mode)"
    fi

    if [ $failed -gt 0 ]; then
        log_warn "VPK push: $success/${#container_array[@]} succeeded ($failed failed)"
        return 1
    fi

    log_ok "VPK push complete - ${BOLD}$success/${#container_array[@]}${RESET} server(s) synced"
    return 0
}

# One background worker per container event: writes the status file lifecycle
# (queued -> updating? -> verifying -> pushing? -> done/failed) that the egg's
# boot handshake reads. Runs as a subshell via `_push_worker event container &`.
_push_worker() {
    local event="$1" container="$2"
    local lock_file="/var/lock/cs2-vpk-push-${container}.lock"
    local reg_file="$DAEMON_REGISTRY_DIR/${container}"
    local _slot=0 _locked=0 _registered=0
    # Release only what this worker actually holds, even on crash.
    # Unconditional cleanup would free another worker's live lock.
    trap '[ "$_locked" = 1 ] && rmdir "$lock_file" 2>/dev/null; [ "$_registered" = 1 ] && rm -f "$reg_file" 2>/dev/null; [ "$_slot" = 1 ] && echo >&"$_DAEMON_WORKER_FD"' EXIT

    # Debounce: only applied to create events (Wings fires create+start together,
    # so create handles initial push and start can skip the heavy work).
    local debounce_file="/tmp/cs2-vpk-pushed-${container}"
    if [ "$event" != "start" ] && [ -f "$debounce_file" ]; then
        local last_push now
        last_push=$(cat "$debounce_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        [ $((now - last_push)) -lt 30 ] && exit 0
    fi

    local volume_path
    volume_path=$(_volume_path "$container")

    if [ -z "$volume_path" ] || [ ! -d "$volume_path" ]; then
        exit 0
    fi

    # Register for the refresher and signal "queued" BEFORE waiting for a slot:
    # on a saturated pool the egg sees a live queue position instead of silence.
    { echo "pid=$BASHPID"; echo "volume=$volume_path"; echo "enq=$(date +%s)"; } > "$reg_file" 2>/dev/null && _registered=1
    local qpos
    qpos=$(ls "$DAEMON_REGISTRY_DIR" 2>/dev/null | wc -l | tr -d ' ')
    _write_status "$container" "$volume_path" "queued" "$qpos"

    # Acquire a worker slot here, inside the subshell: the event loop
    # must never block on a saturated pool, or symlink mounts for later
    # events would stall and containers time out waiting on markers (#51).
    read -r <&"$_DAEMON_WORKER_FD" || exit 0
    _slot=1

    # Per-container push lock: wait for a concurrent cron push / sibling worker
    # instead of giving up - the fresh queued status keeps the egg waiting.
    local waited=0
    while ! mkdir "$lock_file" 2>/dev/null; do
        if [ "$waited" -ge 3600 ]; then
            log_warn "Push lock busy for ${BOLD}$container${RESET} after 1h - reporting failed"
            _write_status "$container" "$volume_path" "failed"
            exit 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    _locked=1

    # Central CS2 update in progress? Wait it out instead of verifying against a
    # half-written CS2_DIR. The shared lock is then HELD until worker exit (fd
    # closes with the subshell) so an update can't start mid-verify/push either.
    local _ufd
    touch "$CENTRAL_UPDATE_LOCK" 2>/dev/null || true
    exec {_ufd}<"$CENTRAL_UPDATE_LOCK"
    if ! flock -n -s "$_ufd"; then
        log_info "Central update running - ${BOLD}$container${RESET} waiting for it to finish"
        _write_status "$container" "$volume_path" "updating"
        if ! flock -s -w 3600 "$_ufd"; then
            log_warn "Central update still running after 1h - reporting failed for ${BOLD}$container${RESET}"
            _write_status "$container" "$volume_path" "failed"
            exit 0
        fi
        log_info "Central update finished - ${BOLD}$container${RESET} proceeding"
    fi

    if [ "$event" = "start" ]; then
        _write_status "$container" "$volume_path" "verifying"
        if _verify_volume_vpks "$volume_path"; then
            mkdir -p "$volume_path/egg" 2>/dev/null
            # ! TODO: Remove marker touch after 2026-10-01 (pre-status-file eggs)
            touch "$volume_path/egg/.daemon-managed" 2>/dev/null || true
            chown -R pterodactyl:pterodactyl "$volume_path/egg" 2>/dev/null || true
            _write_status "$container" "$volume_path" "done"
            exit 0
        fi
        log_warn "Container has missing/broken VPKs: ${BOLD}$container${RESET} - self-healing push..."
    else
        log_info "Container started: ${BOLD}$container${RESET} - pushing game files before first start..."
    fi

    if _sync_to_volume "$container" "$volume_path"; then
        date +%s > "$debounce_file"
        log_ok "Game files pushed to ${BOLD}$container${RESET}"
    else
        log_warn "Push failed for ${BOLD}$container${RESET}"
    fi
}

# Shared handling for live docker events and reconcile sweeps.
_handle_container_event() {
    local event="$1" container="$2"

    # Treat restart identically to start for all downstream logic.
    [ "$event" = "restart" ] && event="start"

    # symlink mode: nsenter-mount on every start event; stays in main thread
    # (fast ~100ms per server). Legacy marker touch kept for pre-status-file eggs
    # (! TODO: remove the marker touch after 2026-10-01).
    if [ "$event" = "start" ] && [ "$VPK_PUSH_METHOD" = "symlink" ]; then
        if _nsenter_mount "$container" "$CS2_DIR" "/tmp/cs2-shared"; then
            log_info "CS2_DIR mounted into ${BOLD}$container${RESET} at /tmp/cs2-shared"
            local _vol_path
            _vol_path=$(_volume_path "$container")
            if [ -n "$_vol_path" ] && [ -d "$_vol_path/egg" ]; then
                touch "$_vol_path/egg/.daemon-managed" 2>/dev/null || true
                chown pterodactyl:pterodactyl "$_vol_path/egg/.daemon-managed" 2>/dev/null || true
            fi
        else
            log_warn "nsenter mount failed for $container - symlinks may not resolve"
        fi
    fi

    _push_worker "$event" "$container" &
}

# Sweep all running matching containers as synthetic start events. Covers boots
# whose docker event the daemon missed (daemon restart, event stream drop).
_reconcile_running_containers() {
    local c
    while IFS= read -r c; do
        [ -n "$c" ] && _handle_container_event start "$c"
    done < <(_matching_containers)
}

# Health check for the whole centralized setup. Read-only diagnosis, except a
# few unambiguously safe fixes (daemon restart on stale in-memory code, orphaned
# push locks). Everything else prints the exact command to run. Every check must
# be failure-guarded: set -e is active and a dying doctor helps nobody.
run_doctor() {
    headline "CS2 Egg Doctor"

    local fails=0 warns=0 fixed=0
    _ok()    { echo -e "  ${GREEN}OK${RESET}     $*" >&2; }
    _dwarn() { echo -e "  ${YELLOW}WARN${RESET}   $*" >&2; warns=$((warns + 1)); }
    _dfail() { echo -e "  ${RED}FAIL${RESET}   $*" >&2; fails=$((fails + 1)); }
    _dfixed(){ echo -e "  ${CYAN}FIXED${RESET}  $*" >&2; fixed=$((fixed + 1)); }

    section "Script & service"

    # where does systemd actually point?
    local exec_path=""
    if [ -f /etc/systemd/system/cs2-vpk-daemon.service ]; then
        exec_path=$(grep -m1 '^ExecStart=' /etc/systemd/system/cs2-vpk-daemon.service 2>/dev/null | cut -d= -f2- | awk '{print $1}' || true)
    fi
    [ -z "$exec_path" ] && exec_path="/usr/local/bin/update-cs2-centralized.sh"

    local disk_version=""
    if [ -x "$exec_path" ]; then
        disk_version=$(grep -m1 '^# Version:' "$exec_path" 2>/dev/null | awk '{print $3}' || true)
        _ok "Service script exists: $exec_path (version ${disk_version:-unknown})"
    else
        _dfail "Service script missing/not executable at $exec_path - reinstall: curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/misc/install-cs2-update.sh -o /tmp/i.sh && sudo bash /tmp/i.sh"
    fi
    if [ "$(readlink -f "$0" 2>/dev/null || true)" != "$(readlink -f "$exec_path" 2>/dev/null || true)" ]; then
        _dwarn "You are running $0 but the service runs $exec_path - edits to this copy do NOT reach the daemon/cron"
    fi

    # cron: /etc/cron.d/cs2-update is the managed scheduler - converge to it,
    # always pointing at the service script (exec_path), never at stray copies
    local cron_ok=false
    if [ -f /etc/cron.d/cs2-update ]; then
        local cron_path
        cron_path=$(grep -v '^#' /etc/cron.d/cs2-update 2>/dev/null | grep -o '/[^ ]*update-cs2-centralized\.sh' | head -1 || true)
        if [ -n "$cron_path" ] && [ ! -x "$cron_path" ]; then
            if [ -x "$exec_path" ] && sed -i "s|$cron_path|$exec_path|" /etc/cron.d/cs2-update 2>/dev/null; then
                _dfixed "Cron pointed at missing $cron_path - rewrote to $exec_path (schedule kept)"
                cron_ok=true
            else
                _dfail "Cron points at $cron_path but the file is missing - CS2 updates are NOT running"
            fi
        else
            _ok "Cron job registered (/etc/cron.d/cs2-update)"
            cron_ok=true
        fi
    elif [ -x "$exec_path" ]; then
        if {
            echo "# CS2 Centralized Update - restored by --doctor"
            echo "SHELL=/bin/bash"
            echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
            echo "* * * * * root $exec_path >> /var/log/cs2-update.log 2>&1"
        } > /etc/cron.d/cs2-update 2>/dev/null; then
            chmod 644 /etc/cron.d/cs2-update 2>/dev/null || true
            _dfixed "Cron file was missing - recreated /etc/cron.d/cs2-update (every minute, rate-limited by UPDATE_CHECK_INTERVAL)"
            cron_ok=true
        else
            _dwarn "Cron file /etc/cron.d/cs2-update missing and could not recreate it - automatic CS2 updates are off"
        fi
    else
        _dwarn "Cron file /etc/cron.d/cs2-update missing - automatic CS2 updates are off (installer recreates it)"
    fi

    # hand-made entries in root's personal crontab (the installer never writes there)
    local user_cron user_cron_path
    user_cron=$(crontab -l 2>/dev/null | grep -v '^#' | grep 'update-cs2-centralized\.sh' || true)
    if [ -n "$user_cron" ]; then
        user_cron_path=$(echo "$user_cron" | grep -o '/[^ ]*update-cs2-centralized\.sh' | head -1 || true)
        if $cron_ok; then
            # duplicate scheduler: the managed cron.d covers it, drop the crontab line
            local remaining_cron
            remaining_cron=$(crontab -l 2>/dev/null | grep -v 'update-cs2-centralized\.sh' || true)
            if printf '%s\n' "$remaining_cron" | crontab - 2>/dev/null; then
                _dfixed "Removed duplicate update line from root's crontab (kept /etc/cron.d/cs2-update). Removed: $user_cron"
            else
                _dwarn "Update scheduled TWICE: /etc/cron.d/cs2-update AND root's crontab ($user_cron_path) - remove the crontab line: crontab -e"
            fi
        elif [ -n "$user_cron_path" ] && [ ! -x "$user_cron_path" ]; then
            _dfail "root's crontab runs $user_cron_path but the file is missing - remove the line (crontab -e) and reinstall for a managed cron"
        else
            _dwarn "Update runs from root's crontab ($user_cron_path) - the installer manages /etc/cron.d/cs2-update instead, consider reinstalling"
        fi
    fi

    # service state + stale in-memory code detection
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet cs2-vpk-daemon 2>/dev/null; then
            local main_pid proc_start script_mtime
            main_pid=$(systemctl show -p MainPID --value cs2-vpk-daemon 2>/dev/null || echo 0)
            proc_start=$(stat -c %Z "/proc/$main_pid" 2>/dev/null || echo 0)
            script_mtime=$(stat -c %Y "$exec_path" 2>/dev/null || echo 0)
            if [ "$script_mtime" -gt "$proc_start" ] 2>/dev/null && [ "$proc_start" -gt 0 ]; then
                if systemctl restart cs2-vpk-daemon 2>/dev/null; then
                    _dfixed "Daemon was running OLDER code than the script on disk - restarted to load it"
                else
                    _dfail "Daemon runs older code than on disk and restart failed - run: systemctl restart cs2-vpk-daemon"
                fi
            else
                _ok "Daemon active (pid $main_pid) and running the on-disk code"
            fi
        elif [ -x "$exec_path" ]; then
            if systemctl restart cs2-vpk-daemon 2>/dev/null && systemctl is-active --quiet cs2-vpk-daemon 2>/dev/null; then
                _dfixed "Daemon was not running - started it"
            else
                _dfail "Daemon not running and restart failed - check: journalctl -u cs2-vpk-daemon -n 50"
            fi
        else
            _dfail "Daemon not running (no script to start) - reinstall first, then: systemctl restart cs2-vpk-daemon"
        fi
        # crash-loop evidence in the recent journal
        local exec_fails
        exec_fails=$(journalctl -u cs2-vpk-daemon --since "-10 min" --no-pager 2>/dev/null | grep -c "Failed at step EXEC" || true)
        [ "${exec_fails:-0}" -gt 0 ] && _dwarn "Service crash-looped ${exec_fails}x in the last 10 min (203/EXEC = missing script) - recheck after the fixes above"
    else
        _dwarn "systemd not found - cannot check the daemon service"
    fi

    section "Dependencies"

    command -v docker >/dev/null 2>&1 && _ok "docker present" || _dfail "docker missing - required for push/restart"

    # installable deps: the script already apt-gets steamcmd libs on its own,
    # so the doctor may install these small ones too instead of just complaining
    _dep_check() {
        local cmd="$1" pkg="$2" why="$3"
        if command -v "$cmd" >/dev/null 2>&1; then
            _ok "$cmd present${why:+ ($why)}"
        elif command -v apt-get >/dev/null 2>&1 && \
             DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$pkg" >/dev/null 2>&1; then
            _dfixed "$cmd was missing - installed $pkg"
        else
            _dfail "$cmd missing${why:+ ($why)} - install: apt-get install -y $pkg"
        fi
    }
    _dep_check rsync rsync ""
    if [ "$VPK_PUSH_METHOD" = "symlink" ]; then
        _dep_check python3 python3 "symlink mounts"
        local kver kmaj kmin
        kver=$(uname -r 2>/dev/null || echo 0.0)
        kmaj=${kver%%.*}; kmin=${kver#*.}; kmin=${kmin%%.*}
        if [ "${kmaj:-0}" -gt 5 ] 2>/dev/null || { [ "${kmaj:-0}" -eq 5 ] && [ "${kmin:-0}" -ge 2 ]; } 2>/dev/null; then
            _ok "Kernel $kver (>= 5.2 needed for symlink mounts)"
        else
            _dfail "Kernel $kver too old for symlink mounts (needs 5.2+) - switch VPK_PUSH_METHOD to hardlink/copy"
        fi
    fi

    section "Central files"

    if [ -d "$CS2_DIR" ]; then
        local buildid vpk_count
        buildid=$(get_local_version)
        vpk_count=$(find "$CS2_DIR" -type f -name '*.vpk' 2>/dev/null | wc -l | tr -d ' ')
        if [ "$buildid" = "unknown" ] || [ "${vpk_count:-0}" -eq 0 ]; then
            _dfail "CS2_DIR ($CS2_DIR) exists but looks incomplete (buildid: $buildid, VPKs: $vpk_count) - run: $exec_path"
        else
            _ok "CS2_DIR healthy: buildid $buildid, $vpk_count VPKs"
        fi
    else
        _dfail "CS2_DIR ($CS2_DIR) does not exist - first update run pending: $exec_path"
    fi
    local free_kb
    free_kb=$(df -Pk "$(dirname "$CS2_DIR")" 2>/dev/null | awk 'NR==2 {print $4}' || true)
    if [[ "$free_kb" =~ ^[0-9]+$ ]]; then
        if [ "$free_kb" -lt 10485760 ]; then
            _dwarn "Low disk space on CS2_DIR filesystem ($((free_kb / 1048576)) GB free) - updates and fallbacks will fail without headroom"
        else
            _ok "Disk space: $((free_kb / 1048576)) GB free on CS2_DIR filesystem"
        fi
    fi

    section "Servers"

    if command -v docker >/dev/null 2>&1; then
        local container volume state ts age now checked=0
        now=$(date +%s)
        while IFS= read -r container; do
            [ -z "$container" ] && continue
            checked=$((checked + 1))
            volume=$(_volume_path "$container")
            if [ -z "$volume" ] || [ ! -d "$volume" ]; then
                _dwarn "$container: cannot resolve volume path"
                continue
            fi
            if [ -f "$volume/egg/.daemon-status" ]; then
                state=$(grep -m1 '^state=' "$volume/egg/.daemon-status" 2>/dev/null | cut -d= -f2 || true)
                ts=$(grep -m1 '^ts=' "$volume/egg/.daemon-status" 2>/dev/null | cut -d= -f2 || true)
                [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
                age=$((now - ts))
                case "$state" in
                    done)   _ok "$container: status done ($((age / 60)) min ago)" ;;
                    failed) _dwarn "$container: last push FAILED - server likely fell back to SteamCMD, check journalctl around $(date -d "@$ts" 2>/dev/null || echo "ts $ts")" ;;
                    *)      if [ "$age" -gt 120 ]; then
                                _dwarn "$container: status stuck in '$state' for $((age / 60)) min - worker died? journalctl -u cs2-vpk-daemon"
                            else
                                _ok "$container: push in progress ($state)"
                            fi ;;
                esac
            else
                _dwarn "$container: no .daemon-status yet (old egg image, or daemon has not seen this server since 1.0.49)"
            fi
            # forensic: steamapps in a daemon-managed volume = a past SteamCMD fallback
            if [ -f "$volume/egg/.daemon-status" ] && [ -d "$volume/steamapps" ]; then
                _dwarn "$container: steamapps/ leftovers found - evidence of a past SteamCMD fallback (egg cleans it on next daemon-managed boot)"
            fi
            # symlink targets (/tmp/cs2-shared/...) only resolve INSIDE the container;
            # from the host, rewrite the prefix to CS2_DIR before testing
            local broken=0 link target
            while IFS= read -r link; do
                [ -z "$link" ] && continue
                target=$(readlink "$link" 2>/dev/null || true)
                case "$target" in
                    /tmp/cs2-shared/*) [ -e "$CS2_DIR/${target#/tmp/cs2-shared/}" ] || broken=$((broken + 1)) ;;
                    *)                 [ -e "$link" ] || broken=$((broken + 1)) ;;
                esac
            done < <(find "$volume/game" -name '*.vpk' -type l 2>/dev/null)
            [ "${broken:-0}" -gt 0 ] && _dwarn "$container: $broken broken VPK symlink(s) - egg cleans them on next boot; daemon mount may have failed earlier"
        done < <(_matching_containers)
        [ "$checked" -eq 0 ] && _dwarn "No running containers match SERVER_IMAGE ($SERVER_IMAGE)"
    fi

    section "Locks"

    # ponytail: 2h orphan threshold - workers cap waits at 1h, anything older is a corpse
    local lock removed_locks=0
    while IFS= read -r lock; do
        [ -z "$lock" ] && continue
        rmdir "$lock" 2>/dev/null && removed_locks=$((removed_locks + 1))
    done < <(find /var/lock -maxdepth 1 -name 'cs2-vpk-push-*' -type d -mmin +120 2>/dev/null)
    [ "$removed_locks" -gt 0 ] && _dfixed "Removed $removed_locks orphaned push lock(s) (older than 2h)"
    if [ -f "$CENTRAL_UPDATE_LOCK" ] && command -v flock >/dev/null 2>&1; then
        if ( exec 9<"$CENTRAL_UPDATE_LOCK"; flock -n -s 9 ) 2>/dev/null; then
            _ok "No central update in progress"
        else
            _ok "Central CS2 update currently running (restarting servers will wait for it)"
        fi
    fi

    section "Self-update"

    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$REMOTE_SCRIPT_URL" 2>/dev/null || echo 000)
    case "$http_code" in
        200) _ok "Update source reachable (branch: $GITHUB_BRANCH)" ;;
        404) _dwarn "Branch '$GITHUB_BRANCH' gone from GitHub - self-update will switch to main on its next run" ;;
        *)   _dwarn "GitHub unreachable (HTTP $http_code) - self-update and --test won't work right now" ;;
    esac

    section "Summary"
    echo -e "  ${YELLOW}$warns warning(s)${RESET}, ${RED}$fails failure(s)${RESET}, ${CYAN}$fixed auto-fixed${RESET}" >&2
    if [ "$fails" -gt 0 ]; then
        log_error "Doctor found $fails blocking issue(s) - fix them with the commands above, then re-run --doctor"
        return 1
    fi
    if [ "$fixed" -gt 0 ]; then
        log_ok "Doctor applied $fixed fix(es) - re-run --doctor to confirm everything is green"
    else
        log_ok "Everything looks healthy"
    fi
    return 0
}

# Download the protocol test suite + the egg helper it exercises from GitHub
# (tracks GITHUB_BRANCH like self-update), run it in a temp dir, clean up.
# Tests the branch's logic, not the installed image - a smoke check for support.
run_protocol_test() {
    section "Protocol Self-Test"

    local tmp
    tmp=$(mktemp -d /tmp/cs2-egg-test-XXXXXX) || { log_error "mktemp failed"; exit 1; }
    trap 'rm -rf "$tmp"' EXIT

    local base="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
    mkdir -p "$tmp/misc" "$tmp/docker/scripts"
    local f
    for f in misc/protocol-test.sh docker/scripts/update_helper.sh; do
        if ! curl -fsSL --max-time 30 "$base/$f" -o "$tmp/$f"; then
            log_error "Failed to download $f from GitHub (branch: $GITHUB_BRANCH)"
            exit 1
        fi
    done

    log_info "Running boot-handshake tests (branch: ${BOLD}$GITHUB_BRANCH${RESET})..."
    if bash "$tmp/misc/protocol-test.sh" >&2; then
        log_ok "Protocol self-test passed"
        exit 0
    fi
    log_error "Protocol self-test FAILED - please report this with the output above"
    exit 1
}

run_event_daemon() {
    section "VPK Push Daemon"

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required for daemon mode"
        exit 1
    fi

    if [ -z "$SERVER_IMAGE" ]; then
        log_error "SERVER_IMAGE must be configured for daemon mode"
        exit 1
    fi

    # Build --filter image= args for each configured image
    local images="${SERVER_IMAGE//,/ }"
    local filter_args=()
    for img in $images; do
        filter_args+=(--filter "image=$img")
    done

    log_ok "Daemon started - watching for container start events"
    log_info "Script version: ${BOLD}$(grep -m1 '^# Version:' "$0" | awk '{print $3}')${RESET}"
    log_info "Images: ${BOLD}$SERVER_IMAGE${RESET}"
    log_info "Push method: ${BOLD}$VPK_PUSH_METHOD${RESET}"
    log_info "CS2 source: ${BOLD}$CS2_DIR${RESET}"
    echo "" >&2

    local _max_workers="$MAX_WORKERS"
    local _fifo
    _fifo=$(mktemp -u /tmp/cs2-daemon-slots-XXXXXX)
    mkfifo "$_fifo"
    exec {_DAEMON_WORKER_FD}<>"$_fifo"
    rm -f "$_fifo"
    for _i in $(seq 1 "$_max_workers"); do echo >&"$_DAEMON_WORKER_FD"; done

    log_info "Worker pool: ${BOLD}${_max_workers}${RESET} parallel workers (MAX_WORKERS)"
    echo "" >&2

    # Fresh daemon = no live workers: wipe the registry, then start the status
    # refresher that keeps waiting eggs' status files fresh every 3s.
    rm -rf "$DAEMON_REGISTRY_DIR" 2>/dev/null || true
    mkdir -p "$DAEMON_REGISTRY_DIR" 2>/dev/null || true
    _status_refresher &
    _REFRESHER_PID=$!

    # Refresher never exits on its own - kill it first or `wait` would hang.
    trap 'kill "$_REFRESHER_PID" 2>/dev/null; wait; exec {_DAEMON_WORKER_FD}>&-' EXIT
    trap 'kill "$_REFRESHER_PID" 2>/dev/null; wait; exec {_DAEMON_WORKER_FD}>&-; exit 130' INT
    trap 'kill "$_REFRESHER_PID" 2>/dev/null; wait; exec {_DAEMON_WORKER_FD}>&-; exit 143' TERM

    # Outer loop: reconnect if the docker events stream drops (daemon restart, etc.)
    while true; do
        # Catch containers whose events we missed (daemon downtime / stream drop):
        # verify-only for healthy volumes, so the sweep is cheap.
        _reconcile_running_containers

        while IFS=' ' read -r event container; do
            [[ -z "$container" ]] && continue
            _handle_container_event "$event" "$container"
        done < <(
            docker events \
                --filter type=container \
                --filter event=create \
                --filter event=start \
                --filter event=restart \
                "${filter_args[@]}" \
                --format '{{.Action}} {{.Actor.Attributes.name}}' 2>/dev/null
        )

        log_warn "Docker event stream ended - reconnecting in 5s..."
        sleep 5
    done
}

# ============================================================================
# SELF-UPDATE FUNCTIONS
# ============================================================================

_download_script_to() {
    local dest="$1"
    local download_error
    download_error=$(curl \
        --max-time 30 \
        --connect-timeout 10 \
        --retry 2 \
        --retry-delay 5 \
        --fail \
        --silent \
        --show-error \
        --location \
        -o "$dest" \
        "$REMOTE_SCRIPT_URL" 2>&1) || {
        log_warn "Failed to download update from GitHub (branch: ${GITHUB_BRANCH})"
        [ -n "$download_error" ] && echo "$download_error" | head -n 2 >&2
        return 1
    }
    return 0
}

# Rewrite this script's own GITHUB_BRANCH line to main (atomic copy + mv, the
# running bash keeps reading the old inode). Used when a testing branch (e.g.
# dev) was merged and deleted, so self-update doesn't dead-end on 404 forever.
_persist_branch_to_main() {
    local tmp
    tmp=$(mktemp "$(dirname "$0")/.$(basename "$0").branch.XXXXXX" 2>/dev/null) || return 0
    if cp "$0" "$tmp" 2>/dev/null && sed -i 's/^GITHUB_BRANCH=.*/GITHUB_BRANCH="main"/' "$tmp" 2>/dev/null; then
        chmod +x "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$0" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
        rm -f "$tmp" 2>/dev/null
    fi
    return 0
}

download_and_validate_update() {
    # Stage next to $0 so the final mv is an atomic same-filesystem rename;
    # /tmp can be a separate tmpfs where mv degrades to copy (crash = broken script)
    local temp_script
    temp_script=$(mktemp "$(dirname "$0")/.$(basename "$0").new.XXXXXX") || return 1

    if ! _download_script_to "$temp_script"; then
        # Testing branch merged & deleted? Only a confirmed 404 switches to main -
        # a network hiccup must not pull a tester off their branch.
        local http_code=""
        if [ "$GITHUB_BRANCH" != "main" ]; then
            http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$REMOTE_SCRIPT_URL" 2>/dev/null || echo 000)
        fi
        if [ "$http_code" = "404" ]; then
            log_warn "Branch '${GITHUB_BRANCH}' no longer exists on GitHub (merged?) - switching self-update to main"
            GITHUB_BRANCH="main"
            REMOTE_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/misc/${SCRIPT_FILENAME}"
            _persist_branch_to_main
            if ! _download_script_to "$temp_script"; then
                rm -f "$temp_script"
                return 1
            fi
        else
            rm -f "$temp_script"
            return 1
        fi
    fi

    # Validate non-empty
    if [ ! -s "$temp_script" ]; then
        log_error "Downloaded file is empty"
        rm -f "$temp_script"
        return 1
    fi

    # Validate shebang
    if ! head -n1 "$temp_script" | grep -q '^#!/bin/bash'; then
        log_error "Invalid script format (missing shebang)"
        rm -f "$temp_script"
        return 1
    fi

    # Validate bash syntax
    local syntax_error
    syntax_error=$(bash -n "$temp_script" 2>&1) || {
        log_error "Downloaded script has syntax errors"
        echo "$syntax_error" | head -n 3 >&2
        rm -f "$temp_script"
        return 1
    }

    # Check minimum size (script should be reasonably large)
    local file_size=$(stat -f%z "$temp_script" 2>/dev/null || stat -c%s "$temp_script" 2>/dev/null)
    if [ "$file_size" -lt 1000 ]; then
        log_error "Downloaded file suspiciously small (${file_size} bytes)"
        rm -f "$temp_script"
        return 1
    fi

    echo "$temp_script"
}

create_versioned_backup() {
    mkdir -p "$UPDATE_BACKUP_DIR"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$UPDATE_BACKUP_DIR/$(basename "$0").$timestamp"

    cp "$0" "$backup_file"
    log_info "Backup created: ${BOLD}$(basename "$backup_file")${RESET}"

    # Cleanup old backups
    local backup_count=$(ls -1 "$UPDATE_BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$backup_count" -gt "$UPDATE_KEEP_BACKUPS" ]; then
        ls -t "$UPDATE_BACKUP_DIR"/* | tail -n +$((UPDATE_KEEP_BACKUPS + 1)) | xargs rm -f 2>/dev/null
    fi
}

preserve_user_config() {
    local new_script="$1"
    local current_script="$0"

    # Config variables to preserve
    local config_vars=(
        "CS2_DIR"
        "STEAMCMD_DIR"
        "SERVER_IMAGE"
        "AUTO_RESTART_SERVERS"
        "VALIDATE_INSTALL"
        "AUTO_UPDATE_SCRIPT"
        "UPDATE_CHECK_INTERVAL"
        "VPK_PUSH_METHOD"
        "MAX_WORKERS"
        "WINGS_CONFIG"
        "GITHUB_BRANCH"
    )

    log_info "Preserving user configuration..."

    # Extract and apply each config value
    for var in "${config_vars[@]}"; do
        # Extract current value from running script (handle quoted values)
        local current_value=$(grep "^${var}=" "$current_script" | head -n1 | cut -d'=' -f2-)

        if [ -n "$current_value" ]; then
            # Escape special characters for sed
            local escaped_value=$(echo "$current_value" | sed 's/[\/&]/\\&/g')

            # Replace in new script (match pattern: VAR="value" or VAR='value' or VAR=value)
            sed -i.bak "s/^${var}=.*/${var}=${escaped_value}/" "$new_script"
        fi
    done

    rm -f "$new_script.bak" 2>/dev/null || true
    log_ok "Configuration preserved"
}

apply_update() {
    local new_script="$1"

    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║              APPLYING SCRIPT UPDATE                         ║"
    log_info "╠════════════════════════════════════════════════════════════╣"
    log_info "║ Backup directory: ${UPDATE_BACKUP_DIR##*/}"
    log_info "║ Restarting with updated version..."
    log_info "╚════════════════════════════════════════════════════════════╝"

    # Preserve user configuration before applying update
    preserve_user_config "$new_script"

    # Atomic replace
    chmod +x "$new_script"
    mv "$new_script" "$0"

    # Update timestamp
    echo "$(date +%s)" > "$UPDATE_CHECK_TIMESTAMP_FILE"

    # Restart the daemon service (if running) so it picks up the new script.
    # The cron-driven invocation runs in a separate process from the systemd daemon,
    # so the daemon would otherwise keep executing the old in-memory code until manual
    # restart. systemctl restart loads the fresh script from disk.
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet cs2-vpk-daemon 2>/dev/null; then
        log_info "Restarting cs2-vpk-daemon service to load new code..."
        systemctl restart cs2-vpk-daemon 2>/dev/null || log_warn "Daemon restart failed - run: systemctl restart cs2-vpk-daemon"
    fi

    # Exec restart (preserves PID, lock file)
    # Use ORIGINAL_ARGS to pass the script's command-line arguments, not function args
    exec "$0" "${ORIGINAL_ARGS[@]}"
}

check_and_apply_updates() {
    # Skip if disabled
    [ "$AUTO_UPDATE_SCRIPT" != "true" ] && return 0

    # Rate limiting (* = check every run, number = minimum seconds between checks)
    if [ "$UPDATE_CHECK_INTERVAL" != "*" ] && [ -f "$UPDATE_CHECK_TIMESTAMP_FILE" ]; then
        local last_check=$(cat "$UPDATE_CHECK_TIMESTAMP_FILE")
        local now=$(date +%s)
        local elapsed=$((now - last_check))

        if [ "$elapsed" -lt "$UPDATE_CHECK_INTERVAL" ]; then
            return 0
        fi
    fi

    section "Script Update Check"
    log_info "Checking for script updates..."

    # Download and validate
    local temp_script
    if ! temp_script=$(download_and_validate_update); then
        # Update timestamp even on failure to respect rate limit
        echo "$(date +%s)" > "$UPDATE_CHECK_TIMESTAMP_FILE"
        log_info "Continuing with current version"
        return 0
    fi

    # Compare versions
    local current_version=$(grep "^# Version:" "$0" 2>/dev/null | head -n1 | awk '{print $3}')
    local new_version=$(grep "^# Version:" "$temp_script" 2>/dev/null | head -n1 | awk '{print $3}')

    # Handle missing version (old script without version header)
    if [ -z "$current_version" ]; then
        current_version="unknown"
    fi
    if [ -z "$new_version" ]; then
        log_warn "Downloaded script missing version header, skipping update"
        rm -f "$temp_script"
        echo "$(date +%s)" > "$UPDATE_CHECK_TIMESTAMP_FILE"
        return 0
    fi

    if [ "$current_version" = "$new_version" ]; then
        log_ok "Script is up to date (version: $current_version)"
        rm -f "$temp_script"
        echo "$(date +%s)" > "$UPDATE_CHECK_TIMESTAMP_FILE"
        return 0
    fi

    # Only update if the remote version is actually newer (sort -V handles semver)
    local newest
    newest=$(printf '%s\n%s\n' "$current_version" "$new_version" | sort -V | tail -n1)
    if [ "$newest" != "$new_version" ]; then
        log_ok "Local version ($current_version) is ahead of remote ($new_version) - skipping"
        rm -f "$temp_script"
        echo "$(date +%s)" > "$UPDATE_CHECK_TIMESTAMP_FILE"
        return 0
    fi

    # Update available
    log_info "New version available: ${BOLD}$current_version${RESET} → ${BOLD}$new_version${RESET}"

    # Apply update
    create_versioned_backup
    apply_update "$temp_script"

    # If we reach here, exec failed (shouldn't happen)
    log_error "Failed to restart with new version"
    return 1
}

main() {
    # Everything here touches root-owned paths (CS2_DIR, /var/cache, /var/lock,
    # panel volumes, docker) - re-exec with sudo like the installer does, instead
    # of failing halfway through with confusing permission errors.
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            log_warn "Requires root - re-executing with sudo..."
            exec sudo bash "$0" "$@"
        fi
        log_error "This script must run as root"
        exit 1
    fi

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --simulate)
                SIMULATE_MODE=true
                shift
                ;;
            --validate)
                VALIDATE_INSTALL="true"
                log_warn "One-shot validate requested: steamcmd will verify every file this run"
                shift
                ;;
            --daemon)
                validate_config
                if [ "$VPK_PUSH_METHOD" = "off" ]; then
                    log_error "Daemon mode requires VPK_PUSH_METHOD to be set (not \"off\")"
                    exit 1
                fi
                run_event_daemon
                exit 0
                ;;
            --test)
                run_protocol_test
                exit 0
                ;;
            --doctor)
                run_doctor
                exit $?
                ;;
            *)
                log_error "Unknown argument: $1"
                echo ""
                echo "Usage: $0 [--simulate] [--validate]"
                echo "       $0 --daemon"
                echo "       $0 --test"
                echo "       $0 --doctor"
                echo ""
                echo "Options:"
                echo "  --simulate    Simulate update mode (skip SteamCMD, trigger restart logic)"
                echo "  --validate    Force one-shot file validation (steamcmd validate), does not persist"
                echo "  --daemon      Run as event listener - push game files on container start"
                echo "  --test        Download + run the protocol test suite, then clean up"
                echo "  --doctor      Health check + safe auto-fixes for the whole setup"
                echo ""
                exit 1
                ;;
        esac
    done

    headline "KitsuneLab CS2 Centralized Update"

    if [ "$SIMULATE_MODE" = "true" ]; then
        log_warn "Running in SIMULATE mode - SteamCMD update will be skipped"
    fi

    section "Pre-flight Checks"

    # Validate configuration
    validate_config

    # Acquire lock to prevent concurrent runs
    acquire_lock
    trap release_lock EXIT
    trap 'release_lock; exit 130' SIGINT
    trap 'release_lock; exit 143' SIGTERM
    trap 'release_lock; exit 129' SIGHUP

    # Check dependencies
    if [ "$AUTO_RESTART_SERVERS" = "true" ] || [ "$VPK_PUSH_METHOD" != "off" ]; then
        if ! command -v docker >/dev/null 2>&1; then
            log_error "Docker is required for VPK push / auto-restart but not installed"
            log_error "Install Docker or set AUTO_RESTART_SERVERS=false and VPK_PUSH_METHOD=off"
            exit 1
        fi
        if ! command -v rsync >/dev/null 2>&1; then
            log_error "rsync is required for VPK push but not installed"
            log_error "Install rsync: apt-get install -y rsync"
            exit 1
        fi
    fi

    log_ok "Dependencies satisfied"
    log_info "CS2 Directory: ${BOLD}$CS2_DIR${RESET}"
    log_info "SteamCMD Directory: ${BOLD}$STEAMCMD_DIR${RESET}"

    # Check and apply script updates (with rate limiting)
    check_and_apply_updates

    install_or_reinstall_steamcmd || exit 1

    # Update CS2 (SteamCMD checks and downloads if needed)
    local update_occurred=false
    if [ "$SIMULATE_MODE" = "true" ]; then
        # Simulate mode: skip SteamCMD but act as if update happened
        section "Simulating CS2 Update"
        log_info "Skipping SteamCMD update (simulate mode)"
        log_ok "Simulated update complete - triggering push and restart logic"
        update_occurred=true
    elif update_cs2; then
        update_occurred=true
    fi

    if [ "$update_occurred" = "true" ]; then
        # A partial push must not abort the run: healthy servers still need their restart
        if ! push_vpk_to_containers; then
            log_warn "Some pushes failed - continuing so synced servers still restart"
        fi
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            restart_docker_containers || log_warn "Some restarts failed - check output above"
        else
            log_info "Auto-restart disabled, servers will pick up new files on next restart"
        fi
    fi

    section "Summary"

    if [ "$SIMULATE_MODE" = "true" ]; then
        log_ok "Simulation completed successfully"
        log_info "Mode: ${BOLD}SIMULATE${RESET} (SteamCMD update skipped)"
    else
        log_ok "CS2 update completed successfully"
    fi

    log_info "Version:    ${BOLD}$(get_local_version)${RESET}"
    log_info "Location:   ${BOLD}$CS2_DIR${RESET}"
    log_info "Push method: ${BOLD}$VPK_PUSH_METHOD${RESET}"

    if [ "$update_occurred" = "true" ]; then
        if [ "$VPK_PUSH_METHOD" != "off" ]; then
            log_info "Game files pushed to server volumes"
        fi
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            if [ "$SIMULATE_MODE" = "true" ]; then
                log_info "Restart logic executed (simulated update)"
            else
                log_info "Servers restarted with latest version"
            fi
        else
            log_info "Servers will pick up new files on next restart"
        fi
    else
        log_info "No update available, servers already on latest version"
    fi
    echo ""
}

# Run main program
main "$@"