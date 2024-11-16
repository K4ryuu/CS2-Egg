#!/bin/bash

# Colors for log messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
NC='\033[0m'
PREFIX="${RED}[KitsuneLab]${WHITE} > "

log_message() {
    local message="$1"
    local type="$2"
    message=$(echo -n "$message")

    case $type in
        running) printf "${PREFIX}${YELLOW}%s${NC}\n" "$message" ;;
        error)   printf "${PREFIX}${RED}%s${NC}\n" "$message" ;;
        success) printf "${PREFIX}${GREEN}%s${NC}\n" "$message" ;;
        debug)   printf "${PREFIX}${WHITE}[DEBUG] %s${NC}\n" "$message" ;;
        *)       printf "${PREFIX}${WHITE}%s${NC}\n" "$message" ;;
    esac
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