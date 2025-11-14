#!/bin/bash
# KitsuneLab CS2 Centralized Update Script
# Automatically updates CS2 files and optionally restarts all affected servers
# Designed for use with VPK Sync feature
#
# Usage: ./update-cs2-centralized.sh [--simulate]
#   --simulate    Skip SteamCMD update, simulate update and trigger restart logic
#
# Version: 1.0.19

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

# Optional: Enable automatic script self-update (true/false)
# Script checks GitHub for updates and auto-replaces itself
# Keeps last 3 versions as backup, validates before applying
AUTO_UPDATE_SCRIPT="true"

# Optional: Interval between update checks in seconds (default: 600 = 10 minutes)
# Script will only check for updates if this interval has elapsed
UPDATE_CHECK_INTERVAL="600"

# ! ============================================================================
# ! DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# ! ============================================================================

# Simulate mode flag (set by --simulate argument)
SIMULATE_MODE=false

# ============================================================================
# INTERNAL CONSTANTS
# ============================================================================

# Self-update configuration (internal)
GITHUB_REPO="K4ryuu/CS2-Egg"
GITHUB_BRANCH="dev"
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

    # Find containers using the specified image (all tags/branches)
    local containers=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep "$SERVER_IMAGE" | cut -f1)

    if [ -z "$containers" ]; then
        log_info "No containers found using image: ${BOLD}$SERVER_IMAGE${RESET}"
        return 0
    fi

    local count=$(echo "$containers" | wc -l | tr -d ' ')
    log_info "Found ${BOLD}$count${RESET} container(s) using image: ${BOLD}$SERVER_IMAGE${RESET}"

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

    while IFS= read -r container; do
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
            ((success++))
        else
            log_warn "Failed to restart ${BOLD}$container${RESET} via Wings API (HTTP $http_code)"
            ((failed++))
        fi
    done <<< "$containers"

    if [ $failed -gt 0 ]; then
        log_warn "Restarted $success/$count container(s) successfully ($failed failed)"
        return 1
    else
        log_ok "All containers restarted successfully (${BOLD}$success/$count${RESET})"
        return 0
    fi
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
    exec "$0" "$@"
}

check_and_apply_updates() {
    # Skip if disabled
    [ "$AUTO_UPDATE_SCRIPT" != "true" ] && return 0

    # Rate limiting
    if [ -f "$UPDATE_CHECK_TIMESTAMP_FILE" ]; then
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
            *)
                log_error "Unknown argument: $1"
                echo ""
                echo "Usage: $0 [--simulate]"
                echo ""
                echo "Options:"
                echo "  --simulate    Simulate update mode (skip SteamCMD, trigger restart logic)"
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

    # Check and apply script updates (with rate limiting)
    check_and_apply_updates

    install_or_reinstall_steamcmd || exit 1

    # Update CS2 (SteamCMD checks and downloads if needed)
    local update_occurred=false
    if [ "$SIMULATE_MODE" = "true" ]; then
        # Simulate mode: skip SteamCMD but act as if update happened
        section "Simulating CS2 Update"
        log_info "Skipping SteamCMD update (simulate mode)"
        log_ok "Simulated update complete - triggering restart logic"
        update_occurred=true

        # Trigger restart logic
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            restart_docker_containers
        else
            log_info "Auto-restart disabled, servers will sync on next restart"
        fi
    elif update_cs2; then
        update_occurred=true
        # Update happened, restart servers if configured
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            restart_docker_containers
        else
            log_info "Auto-restart disabled, servers will sync on next restart"
        fi
    fi

    section "Summary"

    if [ "$SIMULATE_MODE" = "true" ]; then
        log_ok "Simulation completed successfully"
        log_info "Mode: ${BOLD}SIMULATE${RESET} (SteamCMD update skipped)"
    else
        log_ok "CS2 update completed successfully"
    fi

    log_info "Version: ${BOLD}$(get_local_version)${RESET}"
    log_info "Location: ${BOLD}$CS2_DIR${RESET}"

    if [ "$update_occurred" = "true" ]; then
        if [ "$AUTO_RESTART_SERVERS" = "true" ]; then
            if [ "$SIMULATE_MODE" = "true" ]; then
                log_info "Restart logic executed (simulated update)"
            else
                log_info "Servers restarted and synced with latest version"
            fi
        else
            log_info "Servers will sync new files on next restart"
        fi
    else
        log_info "No update available, servers already running latest version"
    fi
    echo ""
}

# Check for post-update health (auto-rollback if needed)
check_update_health "$@"

# Run main program
main "$@"
