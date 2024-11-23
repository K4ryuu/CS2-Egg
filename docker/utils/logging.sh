#!/bin/bash

# Colors and constants - only set if not already defined
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    WHITE='\033[0;37m'
    NC='\033[0m'
fi

# Set PREFIX only if not defined
[ -z "$PREFIX" ] && PREFIX="${RED}[KitsuneLab]${WHITE} > "

# Default values for configuration - only set if not defined
: ${LOG_FILE:="./egg.log"}
: ${LOG_RETENTION_HOURS:=48}
: ${LOG_LEVEL:="INFO"}

# Pre-calculate log level priority if not already set
if [ -z "$LOG_LEVEL_PRIORITY" ]; then
    declare -A log_levels=(
        ["debug"]=0
        ["info"]=1
        ["running"]=2
        ["error"]=3
    )

    get_level_priority() {
        case "$LOG_LEVEL" in
            "DEBUG") echo 0 ;;
            "INFO") echo 1 ;;
            "WARNING") echo 2 ;;
            "ERROR") echo 3 ;;
            *) echo 1 ;; # Default to INFO
        esac
    }

    LOG_LEVEL_PRIORITY=$(get_level_priority)
fi

clean_old_logs() {
    [ "${LOG_FILE_ENABLED:-0}" -eq 1 ] || return 0

    local log_dir="$(dirname "$LOG_FILE")"
    local log_name="$(basename "$LOG_FILE")"

    find "$log_dir" -name "$log_name*" -type f -mmin "+$((LOG_RETENTION_HOURS * 60))" -delete 2>/dev/null
}

log_message() {
    local message="$1"
    local type="${2:-info}"
    local msg_priority="${log_levels[$type]:-1}"

    # Early return if log level is not sufficient
    [ "$msg_priority" -ge "$LOG_LEVEL_PRIORITY" ] || return 0

    # Format message
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    message="${message%[[:space:]]}"

    # Console output with color
    case "$type" in
        running) printf "${PREFIX}${YELLOW}%s${NC}\n" "$message" ;;
        error)   printf "${PREFIX}${RED}%s${NC}\n" "$message" ;;
        success) printf "${PREFIX}${GREEN}%s${NC}\n" "$message" ;;
        debug)   printf "${PREFIX}${WHITE}[DEBUG] %s${NC}\n" "$message" ;;
        *)       printf "${PREFIX}${WHITE}%s${NC}\n" "$message" ;;
    esac
}

handle_error() {
    local exit_code="$?"
    local line_number="${1:-}"
    local last_command="${2:-$BASH_COMMAND}"

    # Handle specific error cases
    case $exit_code in
        127)
            log_message "Command not found: $last_command" "error"
            log_message "Exit code: 127" "error"
            ;;
        0)
            return 0
            ;;
        *)
            if [[ $last_command != *"eval ${STEAMCMD}"* ]]; then
                log_message "Error on line $line_number: $last_command" "error"
                log_message "Exit code: $exit_code" "error"
            fi
            ;;
    esac

    return $exit_code
}