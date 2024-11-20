#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
NC='\033[0m'

PREFIX="${RED}[KitsuneLab]${WHITE} > "

LOG_FILE="./egg.log"
LOG_RETENTION_HOURS=48

clean_old_logs() {
    [[ $LOG_FILE_ENABLED -eq 1 ]] && \
    find "$(dirname "$LOG_FILE")" -name "$(basename "$LOG_FILE")*" -type f -mmin +$((LOG_RETENTION_HOURS * 60)) -delete
}

should_log() {
    local msg_level="$1"
    case "$LOG_LEVEL" in
        "DEBUG") return 0 ;;
        "INFO") [[ "$msg_level" != "debug" ]] && return 0 ;;
        "WARNING") [[ "$msg_level" == "error" || "$msg_level" == "running" ]] && return 0 ;;
        "ERROR") [[ "$msg_level" == "error" ]] && return 0 ;;
    esac
    return 1
}

log_message() {
    local message="$1"
    local type="$2"

    should_log "$type" || return 0

    message=$(echo -n "$message")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$type] $message"

    case $type in
        running) printf "${PREFIX}${YELLOW}%s${NC}\n" "$message" ;;
        error) printf "${PREFIX}${RED}%s${NC}\n" "$message" ;;
        success) printf "${PREFIX}${GREEN}%s${NC}\n" "$message" ;;
        debug) printf "${PREFIX}${WHITE}[DEBUG] %s${NC}\n" "$message" ;;
        *) printf "${PREFIX}${WHITE}%s${NC}\n" "$message" ;;
    esac

    [[ $LOG_FILE_ENABLED -eq 1 ]] && echo "$log_entry" >> "$LOG_FILE"
    clean_old_logs
}

handle_error() {
    local exit_code="$?"
    local last_command="$BASH_COMMAND"

    if [[ $exit_code -eq 127 ]]; then
        log_message "Command not found: $last_command" "error"
        log_message "Exit code: 127" "error"
    elif [[ $last_command == *"${GAMEROOT}/${GAMEEXE}"* ]]; then
        log_message "Server has been shut down" "success"
    elif [[ $last_command != *"eval ${STEAMCMD}"* ]]; then
        log_message "Error occurred while executing: $last_command" "error"
        log_message "Exit code: $exit_code" "error"
    fi
    return $exit_code
}