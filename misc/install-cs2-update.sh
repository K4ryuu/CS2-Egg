#!/bin/bash
# KitsuneLab CS2 Centralized Update - Installer
#
# Sets up:
#   1. Update script   → /usr/local/bin/update-cs2-centralized.sh
#   2. VPK push daemon → systemd service (cs2-vpk-daemon)
#   3. Cron job        → /etc/cron.d/cs2-update (runs as root)
#
# Usage: sudo bash install-cs2-update.sh

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

INSTALL_DEST="/usr/local/bin/update-cs2-centralized.sh"
SERVICE_DEST="/etc/systemd/system/cs2-vpk-daemon.service"
CRON_FILE="/etc/cron.d/cs2-update"
LOG_FILE="/var/log/cs2-update.log"
GITHUB_SCRIPT="https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/update-cs2-centralized.sh"

# ── Colors ────────────────────────────────────────────────────────────────────

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
    BLUE=$'\e[34m'; CYAN=$'\e[36m'; GRAY=$'\e[90m'; RESET=$'\e[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; GRAY=""; RESET=""
fi

log_info()  { echo -e "  ${CYAN}→${RESET}  $*"; }
log_ok()    { echo -e "  ${GREEN}✓${RESET}  $*"; }
log_warn()  { echo -e "  ${YELLOW}!${RESET}  $*"; }
log_error() { echo -e "  ${RED}✗${RESET}  $*" >&2; }
section()   { echo -e "\n${BOLD}${BLUE}── $* ${GRAY}$(printf '─%.0s' {1..40})${RESET}"; }
die()       { log_error "$*"; exit 1; }

# Prompt for yes/no; re-ask on anything else. Empty input uses the default (N).
# Returns 0 for yes, 1 for no.
ask_yes_no() {
    local prompt="$1"
    local reply
    while true; do
        read -rp "$prompt" reply
        reply="${reply:-n}"
        case "$reply" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO])     return 1 ;;
            *) log_warn "Please answer yes or no." ;;
        esac
    done
}

# ── Root check ────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    log_warn "Requires root. Re-executing with sudo..."
    exec sudo bash "$0" "$@"
fi

# ── Stdin reopen (curl|bash fix) ──────────────────────────────────────────────
# When invoked via `curl ... | sudo bash`, stdin is the pipe, not the terminal.
# All `read` calls would receive EOF → silently use defaults or abort.
# Reopen stdin from /dev/tty so interactive prompts actually work.
if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec < /dev/tty
fi

# ── Welcome ───────────────────────────────────────────────────────────────────

clear
echo ""
echo -e "${BOLD}  KitsuneLab CS2 Centralized Update${RESET}  -  Installer"
echo -e "  ${GRAY}github.com/K4ryuu/CS2-Egg${RESET}"
echo ""
echo -e "  Keeps all CS2 servers on the same version automatically."
echo -e "  Downloads game files once, pushes them into every container via symlink"
echo -e "  (saving disk space), and optionally restarts servers after each update."
echo ""
echo -e "  ${GRAY}This installer will:${RESET}"
printf "    ${CYAN}%s${RESET} %-30s ${CYAN}→${RESET}  ${BOLD}%s${RESET}\n" "1." "Download the update script"  "$INSTALL_DEST"
printf "    ${CYAN}%s${RESET} %-30s ${CYAN}→${RESET}  ${GRAY}%s${RESET}\n"  "2." "Walk you through configuration" "(wizard)"
printf "    ${CYAN}%s${RESET} %-30s ${CYAN}→${RESET}  ${BOLD}%s${RESET}\n" "3." "Install the VPK push daemon" "$SERVICE_DEST"
printf "    ${CYAN}%s${RESET} %-30s ${CYAN}→${RESET}  ${BOLD}%s${RESET}\n" "4." "Register a root cron job"   "$CRON_FILE"
echo ""
if ! ask_yes_no "  Proceed? [y/N] "; then
    echo "  Aborted."
    exit 0
fi

# ── Read existing config (if reinstalling) ────────────────────────────────────

declare -A EXISTING

if [[ -f "$INSTALL_DEST" ]]; then
    log_info "Existing installation found - loading current config as defaults..."
    _read_cfg() {
        local val
        val=$(grep "^${1}=" "$INSTALL_DEST" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"') || true
        if [[ -n "$val" ]]; then EXISTING[$1]="$val"; fi
    }
    for _k in STEAMCMD_DIR CS2_DIR VPK_PUSH_METHOD AUTO_RESTART_SERVERS VALIDATE_INSTALL AUTO_UPDATE_SCRIPT UPDATE_CHECK_INTERVAL; do
        _read_cfg "$_k"
    done
    # Normalize legacy "always check" values (0 or 1) → * for display in wizard
    if [[ "${EXISTING[UPDATE_CHECK_INTERVAL]:-}" == "0" || "${EXISTING[UPDATE_CHECK_INTERVAL]:-}" == "1" ]]; then
        EXISTING[UPDATE_CHECK_INTERVAL]="*"
    fi
fi

_default() { echo "${EXISTING[$1]:-$2}"; }

# ── Wizard helpers ────────────────────────────────────────────────────────────

declare -A CFG

# Ask a question. Enter = use default.
# Usage: ask KEY DEFAULT "hint" [options...]
ask() {
    local key="$1" default="$2" hint="$3"
    shift 3
    local -a options=("$@")

    echo ""
    echo -e "  ${BOLD}${key}${RESET}  ${GRAY}(default: ${YELLOW}${default}${GRAY})${RESET}"
    echo -e "  ${DIM}${hint}${RESET}"
    if [[ ${#options[@]} -gt 0 ]]; then echo -e "  ${DIM}Options: $(IFS=' | '; echo "${options[*]}")${RESET}"; fi

    local input
    while true; do
        read -re -i "$default" -p "  > " input
        input="${input:-$default}"

        # If options provided, validate
        if [[ ${#options[@]} -gt 0 ]]; then
            local valid=false
            for opt in "${options[@]}"; do if [[ "$input" == "$opt" ]]; then valid=true; break; fi; done
            if ! $valid; then
                log_warn "Invalid. Options: $(IFS=' | '; echo "${options[*]}")"
                continue
            fi
        fi

        # Path validation
        if [[ "$key" == *_DIR ]]; then
            if [[ ! "$input" =~ ^/[a-zA-Z0-9/_.-]+$ ]]; then
                log_warn "Must be an absolute path (letters, digits, /, -, _, .)"
                continue
            fi
        fi

        CFG[$key]="$input"
        break
    done
}

# ── Configuration wizard ──────────────────────────────────────────────────────

section "Configuration"
echo ""
echo -e "  ${GRAY}Press Enter to accept the default for each option.${RESET}"

ask "STEAMCMD_DIR" "$(_default STEAMCMD_DIR /root/steamcmd)" \
    "Where SteamCMD is installed. Created automatically if missing."

ask "CS2_DIR" "$(_default CS2_DIR /srv/cs2-shared)" \
    "Where SteamCMD downloads CS2 files. Can be any path on the host."

ask "VPK_PUSH_METHOD" "$(_default VPK_PUSH_METHOD symlink)" \
    "How game files are pushed into server volumes after each update.
  symlink  = bind-mount CS2_DIR read-only, ~0 extra disk per server (recommended)
  hardlink = zero real extra disk, but panel quota counts full size
  copy     = full copy per server, most disk usage
  off      = disable push entirely" \
    "symlink" "hardlink" "copy" "off"

ask "AUTO_RESTART_SERVERS" "$(_default AUTO_RESTART_SERVERS true)" \
    "Restart matching containers automatically after a CS2 update." \
    "true" "false"

ask "VALIDATE_INSTALL" "$(_default VALIDATE_INSTALL false)" \
    "Run SteamCMD file validation after each update. Slower, useful for troubleshooting." \
    "true" "false"

ask "AUTO_UPDATE_SCRIPT" "$(_default AUTO_UPDATE_SCRIPT true)" \
    "Self-update the script from GitHub. Keeps last 3 backups, validates before applying." \
    "true" "false"

ask "UPDATE_CHECK_INTERVAL" "$(_default UPDATE_CHECK_INTERVAL '*')" \
    "Min seconds between CS2 update checks. * = every cron run. E.g. 3600 = at most once/hour."

CRON_SCHEDULE="* * * * *"

# ── Summary ───────────────────────────────────────────────────────────────────

section "Summary"
echo ""
printf "    ${GRAY}%-26s${RESET} %s\n" "Script:" "$INSTALL_DEST"
printf "    ${GRAY}%-26s${RESET} %s\n" "Service:" "$SERVICE_DEST"
printf "    ${GRAY}%-26s${RESET} %s  ${GRAY}(every minute)${RESET}\n" "Cron:" "$CRON_FILE"
echo ""
echo -e "  ${BOLD}Configuration:${RESET}"
for key in STEAMCMD_DIR CS2_DIR VPK_PUSH_METHOD AUTO_RESTART_SERVERS VALIDATE_INSTALL AUTO_UPDATE_SCRIPT UPDATE_CHECK_INTERVAL; do
    printf "    ${CYAN}%-26s${RESET} %s\n" "$key" "${CFG[$key]}"
done
echo ""
if ! ask_yes_no "  Install with these settings? [y/N] "; then
    echo "  Aborted."
    exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────

section "Installing"

# 1. Download script
log_info "Downloading update script from ${BOLD}github.com/K4ryuu/CS2-Egg${RESET} ..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$GITHUB_SCRIPT" -o "$INSTALL_DEST" \
        || die "Download failed - check internet access and try again"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$INSTALL_DEST" "$GITHUB_SCRIPT" \
        || die "Download failed - check internet access and try again"
else
    die "Neither curl nor wget found - install one first"
fi
chmod +x "$INSTALL_DEST"
log_ok "Downloaded to $INSTALL_DEST"

# 2. Patch config values
log_info "Applying configuration..."
patch_config() {
    local key="$1" val="$2"
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$INSTALL_DEST"
}
patch_config "CS2_DIR"               "${CFG[CS2_DIR]}"
patch_config "STEAMCMD_DIR"          "${CFG[STEAMCMD_DIR]}"
patch_config "AUTO_RESTART_SERVERS"  "${CFG[AUTO_RESTART_SERVERS]}"
patch_config "VALIDATE_INSTALL"      "${CFG[VALIDATE_INSTALL]}"
patch_config "AUTO_UPDATE_SCRIPT"    "${CFG[AUTO_UPDATE_SCRIPT]}"
patch_config "UPDATE_CHECK_INTERVAL" "${CFG[UPDATE_CHECK_INTERVAL]}"
patch_config "VPK_PUSH_METHOD"       "${CFG[VPK_PUSH_METHOD]}"
log_ok "Configuration applied"

# 3. Systemd service
if command -v systemctl >/dev/null 2>&1; then
    log_info "Installing VPK daemon service..."
    cat > "$SERVICE_DEST" << 'EOF'
[Unit]
Description=CS2 VPK Push Daemon
Documentation=https://github.com/K4ryuu/CS2-Egg
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/update-cs2-centralized.sh --daemon
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cs2-vpk-daemon

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable cs2-vpk-daemon
    if systemctl start cs2-vpk-daemon 2>/dev/null; then
        log_ok "Service installed, enabled and started (cs2-vpk-daemon)"
    else
        log_ok "Service installed and enabled"
        log_warn "Daemon did not start - check: journalctl -u cs2-vpk-daemon"
    fi
else
    log_warn "systemd not found - skipping service install"
    log_warn "Start daemon manually: $INSTALL_DEST --daemon"
fi

# 4. Cron job
log_info "Registering cron job..."
{
    echo "# CS2 Centralized Update - managed by install-cs2-update.sh"
    echo "# Edit schedule or remove this file to disable"
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
    echo "$CRON_SCHEDULE root $INSTALL_DEST >> $LOG_FILE 2>&1"
} > "$CRON_FILE"
chmod 644 "$CRON_FILE"
log_ok "Cron job registered ($CRON_SCHEDULE)"

touch "$LOG_FILE" && chmod 644 "$LOG_FILE"

# ── Done ──────────────────────────────────────────────────────────────────────

section "Done"
echo ""
log_ok "Installation complete."
echo ""
echo -e "  ${BOLD}Quick reference:${RESET}"
printf "    %-26s ${CYAN}%s${RESET}\n" "Run update now:"   "$INSTALL_DEST"
printf "    %-26s ${CYAN}%s${RESET}\n" "Simulate:"         "$INSTALL_DEST --simulate"
printf "    %-26s ${CYAN}%s${RESET}\n" "Daemon status:"    "systemctl status cs2-vpk-daemon"
printf "    %-26s ${CYAN}%s${RESET}\n" "Daemon logs:"      "journalctl -u cs2-vpk-daemon -f"
printf "    %-26s ${CYAN}%s${RESET}\n" "Update logs:"      "tail -f $LOG_FILE"
echo ""
