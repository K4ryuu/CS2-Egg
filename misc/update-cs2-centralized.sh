#!/bin/bash
# KitsuneLab CS2 Centralized Update Script
# Automatically updates CS2 files and pushes them to all server containers
#
# Usage: ./update-cs2-centralized.sh [--simulate]
#        ./update-cs2-centralized.sh --daemon
#
#   --simulate    Skip SteamCMD update, simulate update and trigger restart logic
#   --daemon      Run as event listener daemon - pushes game files instantly when
#                 a CS2 container starts (new server or restart). Install as a
#                 systemd service for automatic startup.
#
# Version: 1.0.43

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

# ! ============================================================================
# ! DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# ! ============================================================================

# Simulate mode flag (set by --simulate argument)
SIMULATE_MODE=false

# Store original arguments for self-update restart
ORIGINAL_ARGS=("$@")

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

# ============================================================================
# STYLING / COLORS
# ============================================================================

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BOLD="\033[1m"; DIM="\033[2m"
    RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
    BLUE="\033[34m"; MAGENTA="\033[35m"; CYAN="\033[36m"; GRAY="\033[90m"
    RESET="\033[0m"
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; GRAY=""; RESET=""
fi

format_bytes() {
    local size="$1"
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then echo "0 B"; return 1; fi
    if   [ "$size" -ge 1099511627776 ]; then awk -v s="$size" 'BEGIN { printf "%.2f TB", s/1099511627776 }'
    elif [ "$size" -ge 1073741824 ];    then awk -v s="$size" 'BEGIN { printf "%.2f GB", s/1073741824 }'
    elif [ "$size" -ge 1048576 ];       then awk -v s="$size" 'BEGIN { printf "%.2f MB", s/1048576 }'
    elif [ "$size" -ge 1024 ];          then awk -v s="$size" 'BEGIN { printf "%.2f KB", s/1024 }'
    else echo "${size} B"; fi
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
        ((errors++))
    fi

    # Validate SteamCMD directory path
    if [[ ! "$STEAMCMD_DIR" =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
        log_error "Invalid STEAMCMD_DIR path: $STEAMCMD_DIR"
        log_error "Path must be absolute and contain only alphanumeric, /, -, _ characters"
        ((errors++))
    fi

    # Validate APP_ID is numeric
    if [[ ! "$APP_ID" =~ ^[0-9]+$ ]]; then
        log_error "Invalid APP_ID: $APP_ID (must be numeric)"
        ((errors++))
    fi

    # Validate Docker configuration if auto-restart or VPK push is enabled
    if [ "$AUTO_RESTART_SERVERS" = "true" ] || [ "$VPK_PUSH_METHOD" != "off" ]; then
        if [ -z "$SERVER_IMAGE" ]; then
            log_error "SERVER_IMAGE is required when AUTO_RESTART_SERVERS=true or VPK_PUSH_METHOD is enabled"
            ((errors++))
        fi
    fi

    # Validate VPK_PUSH_METHOD value
    case "$VPK_PUSH_METHOD" in
        symlink|hardlink|copy|off) ;;
        *)
            log_error "Invalid VPK_PUSH_METHOD: $VPK_PUSH_METHOD (must be: symlink, hardlink, copy, off)"
            ((errors++))
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

run_with_live_tail() {
    local label="$1"; shift
    local cmd=("$@")
    local display_lines=3
    local start_ts=$(date +%s)
    local log_file="/tmp/cs2-update.$$.$RANDOM.log"

    echo -e "${BOLD}${MAGENTA}${label}${RESET}" >&2

    # Run command in background
    "${cmd[@]}" >"$log_file" 2>&1 &
    local pid=$!

    local last_line_count=0
    local displayed_lines=0

    # Monitor output in real-time
    while kill -0 $pid 2>/dev/null; do
        local current_line_count=$(wc -l < "$log_file" 2>/dev/null || echo 0)

        if [ $current_line_count -gt $last_line_count ]; then
            # Move cursor up if we have lines displayed
            if [ $displayed_lines -gt 0 ]; then
                tput cuu $displayed_lines 2>/dev/null || true
            fi

            # Get and display last N lines
            local lines=$(tail -n $display_lines "$log_file" 2>/dev/null)
            displayed_lines=0

            while IFS= read -r line; do
                tput el 2>/dev/null || true
                # Truncate long lines to 100 chars
                echo -e "${DIM}${line:0:100}${RESET}" >&2
                ((displayed_lines++))
            done <<< "$lines"

            # Pad with empty lines if we have fewer than display_lines
            while [ $displayed_lines -lt $display_lines ]; do
                tput el 2>/dev/null || true
                echo "" >&2
                ((displayed_lines++))
            done

            last_line_count=$current_line_count
        fi

        sleep 0.2
    done

    wait $pid
    local ec=$?
    local end_ts=$(date +%s)
    local dur=$((end_ts-start_ts))

    # Clear the displayed lines
    if [ $displayed_lines -gt 0 ]; then
        tput cuu $displayed_lines 2>/dev/null || true
        for i in $(seq 1 $displayed_lines); do
            tput el 2>/dev/null || true
            echo "" >&2
        done
        tput cuu $displayed_lines 2>/dev/null || true
    fi

    if [ $ec -eq 0 ]; then
        log_ok "${label} finished in ${dur}s"
    else
        log_error "${label} failed after ${dur}s (exit $ec)"
        echo "${BOLD}Last 10 lines:${RESET}" >&2
        tail -n 10 "$log_file" >&2 || true

        # Check for specific SteamCMD errors and provide helpful context
        if grep -q "state is 0x" "$log_file" 2>/dev/null; then
            local error_code=$(grep -oP "state is \K0x[0-9a-fA-F]+" "$log_file" 2>/dev/null | head -n1)
            echo "" >&2

            case "$error_code" in
                0x202)
                    log_error "SteamCMD Error 0x202 - Disk space or filesystem issue"
                    log_info "• CS2 requires ~60GB for initial installation"
                    log_info "• After VPK sync, servers only use ~3-8GB each"
                    log_info "• VPK files (~52GB) shared from centralized location"
                    echo "" >&2
                    log_info "Solution: Free up disk space and try again"
                    log_info "Check space: ${BOLD}df -h $(dirname "$CS2_DIR")${RESET}"
                    ;;
                *)
                    log_error "SteamCMD Error $error_code detected"
                    log_info "• Check SteamCMD documentation for details"
                    log_info "• Review full output above for more context"
                    ;;
            esac
        fi

        rm -f "$log_file"
        return $ec
    fi

    rm -f "$log_file"
    return 0
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

    # Build validate flag based on configuration
    local validate_flag=""
    if [ "$VALIDATE_INSTALL" = "true" ]; then
        validate_flag="validate"
    fi

    if ! run_with_live_tail "Checking for updates and downloading" \
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

    # Set permissions
    chown -R pterodactyl:pterodactyl "$CS2_DIR" 2>/dev/null || true
    chmod -R 755 "$CS2_DIR"

    local size=$(du -sh "$CS2_DIR" 2>/dev/null | cut -f1)
    log_info "CS2 directory size: ${BOLD}$size${RESET}"

    # Return 0 if update happened, 1 if already up to date
    [ "$version_before" != "$version_after" ]
}

get_wings_token() {
    if [ ! -f "/etc/pterodactyl/config.yml" ]; then
        return 1
    fi

    local token=$(grep -E '^\s*token:' "/etc/pterodactyl/config.yml" | awk '{print $2}' | tr -d '"' || true)

    if [ -z "$token" ]; then
        return 1
    fi

    echo "$token"
}

get_wings_api_url() {
    # Extract API configuration from config.yml api section
    local api_section=$(sed -n '/^api:/,/^[a-z]/p' "/etc/pterodactyl/config.yml")

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

restart_docker_containers() {
    section "Detecting and Restarting Servers"

    # Normalize SERVER_IMAGE: replace commas with spaces for consistent processing
    local images="${SERVER_IMAGE//,/ }"

    # Build grep pattern for multiple images (escape special chars and join with |)
    local grep_pattern=""
    for img in $images; do
        # Escape special regex characters in image name
        local escaped_img=$(printf '%s' "$img" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
        if [ -z "$grep_pattern" ]; then
            grep_pattern="$escaped_img"
        else
            grep_pattern="$grep_pattern|$escaped_img"
        fi
    done

    # Find containers using any of the specified images
    local containers=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep -E "$grep_pattern" | cut -f1)

    if [ -z "$containers" ]; then
        log_info "No containers found using images: ${BOLD}$images${RESET}"
        return 0
    fi

    # Convert to array for reliable counting and iteration
    local -a container_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && container_array+=("$line")
    done <<< "$containers"

    local count=${#container_array[@]}
    log_info "Found ${BOLD}$count${RESET} container(s) using images: ${BOLD}$images${RESET}"

    # List containers for visibility
    for c in "${container_array[@]}"; do
        echo -e "  ${DIM}→ $c${RESET}" >&2
    done

    # Get Wings API credentials
    local token
    local api_url

    if ! token=$(get_wings_token) || ! api_url=$(get_wings_api_url); then
        log_error "Wings API not available - cannot restart servers"
        log_error "Make sure Wings is installed on this node and the config exists: /etc/pterodactyl/config.yml"
        return 1
    fi

    log_info "Using Wings API for restart"

    local success=0
    local failed=0

    for container in "${container_array[@]}"; do
        # Container name IS the UUID in Pterodactyl
        local uuid="$container"

        # Wings API restart
        local response
        local http_code

        response=$(curl -k -s -w "\n%{http_code}" \
            -X POST "${api_url}/api/servers/${uuid}/power" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d '{"action":"restart"}' \
            2>/dev/null || echo "error\n000")

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

# Sync base files + VPK files from CS2_DIR into a single server volume
_sync_to_volume() {
    local container="$1"
    local dest="$2"
    local src="$CS2_DIR"

    local container_mount_dst="/tmp/cs2-shared"

    # CRITICAL: marker MUST be touched before any push work.
    # The container's detect_daemon_vpk() uses marker presence as the sole daemon-detection signal,
    # so a marker that lags the push would cause entrypoint to race past it and fall through to SteamCMD.
    mkdir -p "$dest/egg" 2>/dev/null && touch "$dest/egg/.daemon-managed" 2>/dev/null
    chown -R pterodactyl:pterodactyl "$dest/egg" 2>/dev/null || true

    # Sync non-VPK base files; exclude per-server configs, gameinfo.gi, and
    # SteamCMD-only dirs (Steam/, steamapps/) — the CS2 server doesn't need them at
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

    # Build image grep pattern (same logic as restart_docker_containers)
    local images="${SERVER_IMAGE//,/ }"
    local grep_pattern=""
    for img in $images; do
        local escaped_img
        escaped_img=$(printf '%s' "$img" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
        [ -z "$grep_pattern" ] && grep_pattern="$escaped_img" || grep_pattern="$grep_pattern|$escaped_img"
    done

    local containers
    containers=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep -E "$grep_pattern" | cut -f1)

    if [ -z "$containers" ]; then
        log_info "No running containers found for VPK push"
        return 0
    fi

    local -a container_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && container_array+=("$line")
    done <<< "$containers"

    log_info "Pushing game files to ${BOLD}${#container_array[@]}${RESET} container(s) [method: ${BOLD}$VPK_PUSH_METHOD${RESET}]"

    local success=0
    local failed=0

    for container in "${container_array[@]}"; do
        local volume_path
        volume_path=$(docker inspect "$container" \
            --format '{{range .Mounts}}{{if eq .Destination "/home/container"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)

        if [ -z "$volume_path" ] || [ ! -d "$volume_path" ]; then
            log_warn "Could not get volume path for $container, skipping"
            ((failed++)) || true
            continue
        fi

        if _sync_to_volume "$container" "$volume_path"; then
            ((success++)) || true
        else
            log_warn "Push failed for ${BOLD}$container${RESET}"
            ((failed++)) || true
        fi
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
    log_info "Images: ${BOLD}$SERVER_IMAGE${RESET}"
    log_info "Push method: ${BOLD}$VPK_PUSH_METHOD${RESET}"
    log_info "CS2 source: ${BOLD}$CS2_DIR${RESET}"
    echo "" >&2

    # Outer loop: reconnect if the docker events stream drops (daemon restart, etc.)
    while true; do
        # Listen for both create (new server) and start (fallback for missed creates)
        docker events \
            --filter type=container \
            --filter event=create \
            --filter event=start \
            "${filter_args[@]}" \
            --format '{{.Action}} {{.Actor.Attributes.name}}' 2>/dev/null | \
        while IFS=' ' read -r event container; do
            [[ -z "$container" ]] && continue

            # symlink mode: nsenter-mount on EVERY start event, before debounce/lock
            # start fires after create (which may still be pushing) - mount must happen regardless
            if [ "$event" = "start" ] && [ "$VPK_PUSH_METHOD" = "symlink" ]; then
                if _nsenter_mount "$container" "$CS2_DIR" "/tmp/cs2-shared"; then
                    log_info "CS2_DIR mounted into ${BOLD}$container${RESET} at /tmp/cs2-shared"
                else
                    log_warn "nsenter mount failed for $container - symlinks may not resolve"
                fi
            fi

            # Debounce: skip push if this container was pushed within the last 30s
            # (Wings fires create + start together; mount above already handled, push can skip)
            local debounce_file="/tmp/cs2-vpk-pushed-${container}"
            if [ -f "$debounce_file" ]; then
                local last_push
                last_push=$(cat "$debounce_file" 2>/dev/null || echo 0)
                local now
                now=$(date +%s)
                if [ $((now - last_push)) -lt 30 ]; then
                    continue
                fi
            fi

            # Per-container lock to avoid overlapping pushes (e.g. create + start firing together)
            local lock_file="/var/lock/cs2-vpk-push-${container}.lock"
            if ! mkdir "$lock_file" 2>/dev/null; then
                continue
            fi

            local volume_path
            volume_path=$(docker inspect "$container" \
                --format '{{range .Mounts}}{{if eq .Destination "/home/container"}}{{.Source}}{{end}}{{end}}' \
                2>/dev/null)

            if [ -z "$volume_path" ] || [ ! -d "$volume_path" ]; then
                rmdir "$lock_file" 2>/dev/null || true
                continue
            fi

            if [ "$event" = "start" ]; then
                # skip push if working VPKs already present (create event already handled it)
                if find -L "$volume_path" -maxdepth 6 -name "*.vpk" -type f 2>/dev/null | grep -q .; then
                    # Heartbeat refresh - container's detect_daemon_vpk uses mtime to verify daemon alive
                    mkdir -p "$volume_path/egg" 2>/dev/null && touch "$volume_path/egg/.daemon-managed" 2>/dev/null
                    chown -R pterodactyl:pterodactyl "$volume_path/egg" 2>/dev/null || true
                    rmdir "$lock_file" 2>/dev/null || true
                    continue
                fi
                log_info "Container started without VPK files: ${BOLD}$container${RESET} - pushing now..."
            else
                log_info "Container started: ${BOLD}$container${RESET} - pushing game files before first start..."
            fi

            if _sync_to_volume "$container" "$volume_path"; then
                date +%s > "$debounce_file"
                log_ok "Game files pushed to ${BOLD}$container${RESET}"
            else
                log_warn "Push failed for ${BOLD}$container${RESET}"
            fi

            rmdir "$lock_file" 2>/dev/null || true
        done

        log_warn "Docker event stream ended - reconnecting in 5s..."
        sleep 5
    done
}

# ============================================================================
# SELF-UPDATE FUNCTIONS
# ============================================================================

download_and_validate_update() {
    local temp_script="/tmp/$(basename "$0").new.$$"

    # Download with comprehensive options
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
        -o "$temp_script" \
        "$REMOTE_SCRIPT_URL" 2>&1) || {
        log_warn "Failed to download update from GitHub"
        [ -n "$download_error" ] && echo "$download_error" | head -n 2 >&2
        return 1
    }

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

    # Mark for health check
    touch "$0.updated"

    # Update timestamp
    echo "$(date +%s)" > "$UPDATE_CHECK_TIMESTAMP_FILE"

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

check_update_health() {
    if [ -f "$0.updated" ]; then
        section "Post-Update Health Check"
        log_info "Performing health check after update..."

        # Basic health checks
        if ! command -v sha256sum >/dev/null 2>&1; then
            log_error "Health check failed: required command 'sha256sum' not found"
            rollback_from_failed_update "$@"
            return 1
        fi

        rm "$0.updated"
        log_ok "Health check passed, update successful"
    fi
}

rollback_from_failed_update() {
    log_error "Rolling back to previous version..."

    local latest_backup=$(ls -t "$UPDATE_BACKUP_DIR"/* 2>/dev/null | head -n1)

    if [ -n "$latest_backup" ]; then
        cp "$latest_backup" "$0"
        chmod +x "$0"
        rm -f "$0.updated"
        log_info "Rollback complete, restarting..."
        exec "$0" "$@"
    else
        log_error "No backup found for rollback, manual intervention required"
        log_error "Script location: $0"
        exit 1
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --simulate)
                SIMULATE_MODE=true
                shift
                ;;
            --daemon)
                validate_config
                [ "$VPK_PUSH_METHOD" = "off" ] && {
                    log_error "Daemon mode requires VPK_PUSH_METHOD to be set (not \"off\")"
                    exit 1
                }
                run_event_daemon
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                echo ""
                echo "Usage: $0 [--simulate]"
                echo "       $0 --daemon"
                echo ""
                echo "Options:"
                echo "  --simulate    Simulate update mode (skip SteamCMD, trigger restart logic)"
                echo "  --daemon      Run as event listener - push game files on container start"
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

        push_vpk_to_containers
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            restart_docker_containers
        else
            log_info "Auto-restart disabled, servers will pick up new files on next restart"
        fi
    elif update_cs2; then
        update_occurred=true
        # Push updated game files into server volumes
        push_vpk_to_containers
        # Restart servers if configured
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            restart_docker_containers
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

# Check for post-update health (auto-rollback if needed)
check_update_health "$@"

# Run main program
main "$@"