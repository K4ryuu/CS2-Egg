#!/bin/bash

# Color codes for pretty terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
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
PREFIX="${PREFIX:=${RED}[${PREFIX_TEXT}]${WHITE} > }"

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

clean_old_logs() {
    rotate_logs
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

    # Print to console with appropriate color
    case "$type" in
        running) printf "%b%s%b\n" "${PREFIX}${YELLOW}" "$message" "${NC}" ;;
        error)   printf "%b%s%b\n" "${PREFIX}${RED}" "$message" "${NC}" ;;
        success) printf "%b%s%b\n" "${PREFIX}${GREEN}" "$message" "${NC}" ;;
        warning) printf "%b[WARNING] %s%b\n" "${PREFIX}${YELLOW}" "$message" "${NC}" ;;
        debug)   printf "%b[DEBUG] %s%b\n" "${PREFIX}${WHITE}" "$message" "${NC}" ;;
        *)       printf "%b%s%b\n" "${PREFIX}${WHITE}" "$message" "${NC}" ;;
    esac

    # Also write to file if logging is enabled
    if [[ "${LOG_FILE_ENABLED}" == "1" ]]; then
        mkdir -p "${EGG_LOGS_DIR}"
        local log_file=$(get_log_file_path)
        echo "[$timestamp] [$type] $message" >> "${log_file}"
    fi
}

handle_error() {
    local exit_code=$?
    local line_number="${1:-}"
    local last_command="${2:-$BASH_COMMAND}"

    # Give better error messages based on exit code
    case $exit_code in
        127)
            log_message "Command not found: $last_command" "error"
            log_message "Exit code: 127" "error"
            ;;
        0)
            return 0
            ;;
        *)
            # Don't spam errors from steamcmd - it's noisy enough already
            if [[ $last_command != *"eval ${STEAMCMD}"* ]]; then
                log_message "Error on line $line_number: $last_command" "error"
                log_message "Exit code: $exit_code" "error"
            fi
            ;;
    esac

    return $exit_code
}