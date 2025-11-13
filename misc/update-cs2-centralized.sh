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

# Optional: Pterodactyl Panel URL (for automatic server restart)
# Example: "https://panel.yourdomain.com"
# Leave empty to disable automatic restarts
PTERODACTYL_API_URL=""

# Optional: Pterodactyl Application API Token
# Get from: Admin Panel → Application API → Create New
# Required permissions: servers.read, servers.power
# Leave empty to disable automatic restarts
PTERODACTYL_API_TOKEN=""

# Optional: Docker image filter for server detection
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

    # Validate Pterodactyl configuration if auto-restart is enabled
    if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
        if [[ ! "$PTERODACTYL_API_URL" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
            log_error "Invalid PTERODACTYL_API_URL: $PTERODACTYL_API_URL"
            log_error "Must be a valid HTTP/HTTPS URL"
            ((errors++))
        fi

        if [ -z "$PTERODACTYL_API_TOKEN" ]; then
            log_error "PTERODACTYL_API_TOKEN is required when AUTO_RESTART_SERVERS=true"
            ((errors++))
        fi

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

get_affected_servers() {
    if [ -z "$PTERODACTYL_API_URL" ] || [ -z "$PTERODACTYL_API_TOKEN" ]; then
        log_warn "Pterodactyl API not configured, skipping server detection"
        return 1
    fi

    section "Detecting Affected Servers"
    log_info "Fetching servers from Pterodactyl API..."

    local page=1
    local servers=()

    while true; do
        local response=$(curl -s \
            -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
            -H "Content-Type: application/json" \
            -H "Accept: Application/vnd.pterodactyl.v1+json" \
            "$PTERODACTYL_API_URL/api/application/servers?page=$page")

        if [ -z "$response" ]; then
            log_error "Failed to fetch servers from API"
            return 1
        fi

        local page_servers=$(echo "$response" | jq -r '.data[] | select(.attributes.container.image | contains("'"${SERVER_IMAGE:-k4ryuu-cs2}"'")) | .attributes.identifier' 2>/dev/null || echo "")

        if [ -n "$page_servers" ]; then
            servers+=($page_servers)
        fi

        local next_page=$(echo "$response" | jq -r '.meta.pagination.links.next // empty' 2>/dev/null)
        if [ -z "$next_page" ]; then
            break
        fi

        ((page++))
    done

    if [ ${#servers[@]} -eq 0 ]; then
        log_warn "No servers found using image matching: ${SERVER_IMAGE:-k4ryuu-cs2}"
        return 1
    fi

    log_ok "Found ${BOLD}${#servers[@]}${RESET} server(s) using CS2 image"
    echo "${servers[@]}"
}

restart_servers() {
    local servers=("$@")

    if [ ${#servers[@]} -eq 0 ]; then
        log_warn "No servers to restart"
        return 0
    fi

    section "Restarting Servers"
    log_info "Preparing to restart ${#servers[@]} server(s)..."

    local success=0
    local failed=0

    for server_id in "${servers[@]}"; do
        log_info "Restarting server: ${BOLD}$server_id${RESET}..."

        local response=$(curl -s -w "\n%{http_code}" \
            -X POST \
            -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
            -H "Content-Type: application/json" \
            -H "Accept: Application/vnd.pterodactyl.v1+json" \
            "$PTERODACTYL_API_URL/api/application/servers/$server_id/power" \
            -d '{"signal":"restart"}')

        local http_code=$(echo "$response" | tail -n1)

        if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
            log_ok "Server $server_id restarted successfully"
            ((success++))
        else
            log_error "Failed to restart server $server_id (HTTP $http_code)"
            ((failed++))
        fi

        sleep 1
    done

    if [ $failed -eq 0 ]; then
        log_ok "All servers restarted successfully ($success/$((success+failed)))"
    else
        log_warn "Some servers failed to restart (success: $success, failed: $failed)"
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
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed. Install with: apt-get install curl"
        exit 1
    fi

    # jq is only required if auto-restart is enabled
    if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
        if ! command -v jq >/dev/null 2>&1; then
            log_error "jq is required for auto-restart feature. Install with: apt-get install jq"
            log_error "Or disable auto-restart by setting AUTO_RESTART_SERVERS=false"
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
            if affected_servers=$(get_affected_servers); then
                # Use array to handle many servers without argument list overflow
                IFS=' ' read -r -a server_array <<< "$affected_servers"
                restart_servers "${server_array[@]}"
            fi
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
