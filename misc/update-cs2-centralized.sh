#!/bin/bash
# KitsuneLab CS2 Centralized Update Script
# Automatically updates CS2 files and optionally restarts all affected servers
# Designed for use with VPK Sync feature

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

# Optional: Docker image for server detection (for automatic server restart)
# Servers using this image will be automatically restarted after update
# Examples: "sples1/k4ryuu-cs2", "sples1/k4ryuu-cs2:latest"
SERVER_IMAGE="sples1/k4ryuu-cs2"

# Optional: Enable automatic server restart after update (true/false)
# Set to "false" if you want servers to sync on next manual restart
AUTO_RESTART_SERVERS="false"

# Optional: Validate game files integrity during update (true/false)
# Set to "false" for faster updates (recommended for cron)
# Set to "true" to verify all files (useful for troubleshooting)
VALIDATE_INSTALL="false"

# ! ============================================================================
# ! DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# ! ============================================================================

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

    # Validate Docker configuration if auto-restart is enabled
    if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
        if [ -z "$SERVER_IMAGE" ]; then
            log_error "SERVER_IMAGE is required when AUTO_RESTART_SERVERS=true"
            ((errors++))
        fi
    fi

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
        log_info "If stuck, remove lock file: $lockfile"
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

install_or_reinstall_steamcmd() {
    section "SteamCMD Setup"

    if [ -f "$STEAMCMD_DIR/steamcmd.sh" ] && [ -f "$STEAMCMD_DIR/linux32/steamcmd" ]; then
        log_ok "SteamCMD already installed at $STEAMCMD_DIR"
        chmod +x "$STEAMCMD_DIR/steamcmd.sh" 2>/dev/null || true
        chmod +x "$STEAMCMD_DIR/linux32/steamcmd" 2>/dev/null || true
        return 0
    fi

    log_warn "SteamCMD not found or incomplete, installing..."
    rm -rf "$STEAMCMD_DIR"
    mkdir -p "$STEAMCMD_DIR"

    if ! run_with_live_tail "Downloading SteamCMD" \
        bash -c "cd '$STEAMCMD_DIR' && curl -sqL 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz' | tar zxf -"; then
        log_error "Failed to download SteamCMD"
        return 1
    fi

    chmod +x "$STEAMCMD_DIR/steamcmd.sh"
    chmod +x "$STEAMCMD_DIR/linux32/steamcmd" 2>/dev/null || true
    log_ok "SteamCMD installed successfully"
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
    log_info "Current version: ${BOLD}$version_before${RESET}"

    mkdir -p "$CS2_DIR"

    # Build validate flag based on configuration
    local validate_flag=""
    if [ "$VALIDATE_INSTALL" = "true" ]; then
        validate_flag="validate"
    fi

    if ! run_with_live_tail "Checking for updates and downloading" \
        "$STEAMCMD_DIR/steamcmd.sh" +force_install_dir "$CS2_DIR" +login anonymous +app_update "$APP_ID" $validate_flag +quit; then
        log_error "CS2 update failed"
        return 1
    fi

    local version_after=$(get_local_version)

    if [ "$version_before" = "$version_after" ]; then
        log_ok "CS2 is already up to date (version: $version_after)"
    else
        log_ok "CS2 updated successfully: $version_before → ${BOLD}$version_after${RESET}"
    fi

    log_info "Installing Steam client libraries..."
    mkdir -p "$CS2_DIR/.steam/sdk32" "$CS2_DIR/.steam/sdk64"
    cp -f "$STEAMCMD_DIR/linux32/steamclient.so" "$CS2_DIR/.steam/sdk32/" 2>/dev/null || true
    cp -f "$STEAMCMD_DIR/linux64/steamclient.so" "$CS2_DIR/.steam/sdk64/" 2>/dev/null || true

    log_info "Setting permissions..."
    chown -R pterodactyl:pterodactyl "$CS2_DIR" 2>/dev/null || true
    chmod -R 755 "$CS2_DIR"

    local size=$(du -sh "$CS2_DIR" 2>/dev/null | cut -f1)
    log_info "CS2 directory size: ${BOLD}$size${RESET}"

    # Return 0 if update happened, 1 if already up to date
    [ "$version_before" != "$version_after" ]
}

restart_docker_containers() {
    section "Detecting and Restarting Servers"

    # Find containers using the specified image (all tags/branches)
    local containers=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep "$SERVER_IMAGE" | cut -f1)

    if [ -z "$containers" ]; then
        log_info "No containers found using image: ${BOLD}$SERVER_IMAGE${RESET}*"
        return 0
    fi

    local count=$(echo "$containers" | wc -l | tr -d ' ')
    log_info "Found ${BOLD}$count${RESET} container(s) using image: ${BOLD}$SERVER_IMAGE${RESET}*"

    local success=0
    local failed=0

    while IFS= read -r container; do
        log_info "Restarting container: ${BOLD}$container${RESET}..."

        if docker restart "$container" >/dev/null 2>&1; then
            log_ok "Container $container restarted successfully"
            ((success++))
        else
            log_error "Failed to restart container: $container"
            ((failed++))
        fi

        sleep 0.5
    done <<< "$containers"

    if [ $failed -gt 0 ]; then
        log_warn "Restarted $success/$count container(s) successfully ($failed failed)"
        return 1
    else
        log_ok "All containers restarted successfully (${BOLD}$success/$count${RESET})"
        return 0
    fi
}

main() {
    headline "KitsuneLab CS2 Centralized Update"

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
    if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
        if ! command -v docker >/dev/null 2>&1; then
            log_error "Docker is required for auto-restart feature but not installed"
            log_error "Install Docker or disable auto-restart by setting AUTO_RESTART_SERVERS=false"
            exit 1
        fi
    fi

    log_ok "Dependencies satisfied"
    log_info "CS2 Directory: ${BOLD}$CS2_DIR${RESET}"
    log_info "SteamCMD Directory: ${BOLD}$STEAMCMD_DIR${RESET}"

    install_or_reinstall_steamcmd || exit 1

    # Update CS2 (SteamCMD checks and downloads if needed)
    if update_cs2; then
        # Update happened, restart servers if configured
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            restart_docker_containers
        else
            log_info "Auto-restart disabled, servers will sync on next restart"
        fi
    else
        # No update needed
        log_info "Servers are already running latest version"
    fi

    section "Summary"
    log_ok "CS2 update completed successfully"
    log_info "Version: ${BOLD}$(get_local_version)${RESET}"
    log_info "Location: ${BOLD}$CS2_DIR${RESET}"
    log_info "Servers will sync new files on next restart"
    echo ""
}

main "$@"
