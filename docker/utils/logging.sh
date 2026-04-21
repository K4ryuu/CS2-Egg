#!/bin/bash

# Color codes for pretty terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
GRAY='\033[0;90m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Organized directory structure for all egg-related files
EGG_DIR="${EGG_DIR:=/home/container/egg}"
EGG_LOGS_DIR="${EGG_LOGS_DIR:=${EGG_DIR}/logs}"
EGG_CONFIGS_DIR="${EGG_CONFIGS_DIR:=${EGG_DIR}/configs}"

# Default logging settings (can be overridden by config)
LOG_FILE_ENABLED="${LOG_FILE_ENABLED:=0}"
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:=100}"
LOG_MAX_FILES="${LOG_MAX_FILES:=30}"
LOG_MAX_DAYS="${LOG_MAX_DAYS:=7}"
PREFIX_TEXT="${PREFIX_TEXT:-KitsuneLab}"

# Set up the directory structure
init_egg_directories() {
    mkdir -p "${EGG_DIR}"
    mkdir -p "${EGG_CONFIGS_DIR}"

    # Only create logs directory if logging is actually enabled
    if [[ "${LOG_FILE_ENABLED}" == "1" ]] || [[ "${LOG_FILE_ENABLED}" == "true" ]]; then
        mkdir -p "${EGG_LOGS_DIR}"
    fi
}

# Each day gets its own log file - way easier to manage
get_log_file_path() {
    local date_str=$(date '+%Y-%m-%d')
    echo "${EGG_LOGS_DIR}/${date_str}.log"
}

# Map log levels to priorities for filtering (compatible with older bash)
_get_msg_priority() {
    local type="$1"
    case "$type" in
        "debug") echo 0 ;;
        "info") echo 1 ;;
        "running") echo 2 ;;
        "error") echo 3 ;;
        *) echo 1 ;; # Default to info
    esac
}

# Cache for log level priority calculation (performance optimization)
LOG_LEVEL_PRIORITY_CACHE=""
LOG_LEVEL_CACHE_VALUE=""

get_level_priority() {
    local log_level="${CONSOLE_LOG_LEVEL:-INFO}"

    # Return cached value if log level hasn't changed
    if [[ "$log_level" == "$LOG_LEVEL_CACHE_VALUE" ]] && [[ -n "$LOG_LEVEL_PRIORITY_CACHE" ]]; then
        echo "$LOG_LEVEL_PRIORITY_CACHE"
        return
    fi

    # Calculate and cache new priority
    LOG_LEVEL_CACHE_VALUE="$log_level"
    case "$(echo "$log_level" | tr '[:lower:]' '[:upper:]')" in
        "DEBUG") LOG_LEVEL_PRIORITY_CACHE=0 ;;
        "INFO") LOG_LEVEL_PRIORITY_CACHE=1 ;;
        "WARNING") LOG_LEVEL_PRIORITY_CACHE=2 ;;
        "ERROR") LOG_LEVEL_PRIORITY_CACHE=3 ;;
        *) LOG_LEVEL_PRIORITY_CACHE=1 ;; # Default to INFO
    esac

    echo "$LOG_LEVEL_PRIORITY_CACHE"
}

# Clean up old logs based on size/count/age limits
rotate_logs() {
    [[ "${LOG_FILE_ENABLED}" == "1" ]] || return 0
    [[ -d "${EGG_LOGS_DIR}" ]] || return 0

    # Delete logs older than max_days
    if [[ ${LOG_MAX_DAYS} -gt 0 ]]; then
        find "${EGG_LOGS_DIR}" -name "*.log" -type f -mtime "+${LOG_MAX_DAYS}" -delete 2>/dev/null
    fi

    # Keep only max_files count
    if [[ ${LOG_MAX_FILES} -gt 0 ]]; then
        local file_count=$(find "${EGG_LOGS_DIR}" -name "*.log" -type f | wc -l)
        if [[ ${file_count} -gt ${LOG_MAX_FILES} ]]; then
            find "${EGG_LOGS_DIR}" -name "*.log" -type f -printf '%T+ %p\n' | \
                sort | head -n $((file_count - LOG_MAX_FILES)) | cut -d' ' -f2- | \
                xargs -r rm -f
        fi
    fi

    # If we're using too much disk space, delete oldest logs first
    if [[ ${LOG_MAX_SIZE_MB} -gt 0 ]]; then
        local dir_size_kb=$(du -sk "${EGG_LOGS_DIR}" | cut -f1)
        local max_size_kb=$((LOG_MAX_SIZE_MB * 1024))

        while [[ ${dir_size_kb} -gt ${max_size_kb} ]]; do
            local oldest_log=$(find "${EGG_LOGS_DIR}" -name "*.log" -type f -printf '%T+ %p\n' | sort | head -n 1 | cut -d' ' -f2-)
            [[ -z "${oldest_log}" ]] && break
            rm -f "${oldest_log}"
            dir_size_kb=$(du -sk "${EGG_LOGS_DIR}" | cut -f1)
        done
    fi
}

log_message() {
    local message="$1"
    local type="${2:-info}"
    local msg_priority=$(_get_msg_priority "$type")
    local log_level_priority=$(get_level_priority)

        # Skip if this message doesn't meet our log level threshold
    [[ ${msg_priority} -ge ${log_level_priority} ]] || return 0

    # Clean up the message and add timestamp
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    message="${message%[[:space:]]}"

    # mask_secrets lives in filter.sh; call only when that module is loaded
    # (container entrypoint always loads it; updater subshells don't and don't need it).
    if declare -F mask_secrets >/dev/null 2>&1; then
        message="$(mask_secrets "$message")"
    fi

    # Enterprise-style table output:  PREFIX | LEVEL | message
    # Level tag padded to 5 chars via printf %-5s — aligns columns across levels.
    local level_tag level_color
    case "$type" in
        info)     level_tag="INFO";  level_color="$CYAN" ;;
        success)  level_tag="OK";    level_color="$GREEN" ;;
        warning)  level_tag="WARN";  level_color="$YELLOW" ;;
        error)    level_tag="ERROR"; level_color="$RED" ;;
        debug)    level_tag="DEBUG"; level_color="$GRAY" ;;
        running)  level_tag="RUN";   level_color="$YELLOW" ;;
        *)        level_tag="INFO";  level_color="$WHITE" ;;
    esac

    local sep
    sep=$(printf '%b|%b' "$GRAY" "$NC")

    printf "%b%s%b %s %b%-5s%b %s %b%s%b\n" \
        "$RED" "$PREFIX_TEXT" "$NC" \
        "$sep" \
        "$level_color" "$level_tag" "$NC" \
        "$sep" \
        "$level_color" "$message" "$NC"

    # Also write to file if logging is enabled
    if [[ "${LOG_FILE_ENABLED}" == "1" ]]; then
        mkdir -p "${EGG_LOGS_DIR}"
        local log_file=$(get_log_file_path)
        echo "[$timestamp] [$type] $message" >> "${log_file}"
    fi
}

# Emit an error/warning with a stable code + docs pointer.
# Optional trailing args become "→ <hint>" lines between the code line and the docs link.
# Usage: log_error_code "KL-STM-01" "SteamCMD connection error" "Check: steamstat.us"
ERROR_DOCS_URL="${ERROR_DOCS_URL:-https://github.com/K4ryuu/CS2-Egg/blob/main/docs/advanced/error-codes.md}"

_log_code_common() {
    local severity="$1"; shift
    local code="$1"; shift
    local msg="$1"; shift
    local anchor
    anchor=$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')
    log_message "[$code] $msg" "$severity"
    for hint in "$@"; do
        log_message "  → $hint" "$severity"
    done
    log_message "  → Docs: ${ERROR_DOCS_URL}#${anchor}" "$severity"
}

log_error_code() { _log_code_common "error" "$@"; }
log_warn_code()  { _log_code_common "warning" "$@"; }

handle_error() {
    local exit_code=$?
    local line_number="${1:-}"
    local last_command="${2:-$BASH_COMMAND}"

    case $exit_code in
        127)
            log_message "Command not found: $last_command" "error"
            log_message "Exit code: 127" "error"
            ;;
        0)
            return 0
            ;;
        *)
            log_message "Error on line $line_number: $last_command" "error"
            log_message "Exit code: $exit_code" "error"
            ;;
    esac

    return $exit_code
}