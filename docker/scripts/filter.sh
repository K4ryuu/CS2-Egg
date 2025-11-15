#!/bin/bash

source /utils/logging.sh
source /utils/config.sh

setup_message_filter() {
    if [ "${ENABLE_FILTER:-0}" -ne 1 ]; then
        return 0
    fi

    # Separate exact matches, blocking patterns, and masking patterns for faster lookup
    declare -gA EXACT_PATTERNS=()
    declare -gA CONTAINS_BLOCK=()
    declare -gA CONTAINS_MASK=()

    # STEAM_ACC is for masking, not blocking
    if [ -n "${STEAM_ACC}" ]; then
        local mask=$(printf '%*s' "${#STEAM_ACC}" '' | tr ' ' '*')
        CONTAINS_MASK["${STEAM_ACC}"]="$mask"
    fi

    local config_file="${EGG_CONFIGS_DIR:-/home/container/egg/configs}/console-filter.json"
    local pattern_count=0

    if [ -f "$config_file" ]; then
        local patterns=$(jq -r '.patterns[]' "$config_file" 2>/dev/null)

        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue

            if [[ $pattern == @* ]]; then
                EXACT_PATTERNS["${pattern#@}"]="1"
            else
                CONTAINS_BLOCK["$pattern"]="1"
            fi
            ((pattern_count++))
        done <<< "$patterns"
    fi

    log_message "Console filter active: $pattern_count patterns (${#EXACT_PATTERNS[@]} exact, ${#CONTAINS_BLOCK[@]} contains)" "info"
}

handle_server_output() {
    local line="$1"

    # Early exit for empty lines
    [[ -z "$line" ]] && {
        printf '%s\n' "$line"
        return
    }

    # Early exit if filter disabled
    if [ "${ENABLE_FILTER:-0}" -ne 1 ]; then
        printf '%s\n' "$line"
        return
    fi

    # O(1) hash lookup for exact matches (much faster than iteration)
    if [[ -n "${EXACT_PATTERNS[$line]}" ]]; then
        if [[ "${FILTER_PREVIEW_MODE:-false}" == "true" ]]; then
            log_message "Blocked message: $line" "debug"
        fi
        return
    fi

    local blocked=false
    local modified_line="$line"

    # Check blocking patterns (separate from masking for performance)
    for pattern in "${!CONTAINS_BLOCK[@]}"; do
        if [[ $line == *"$pattern"* ]]; then
            blocked=true
            break
        fi
    done

    # Apply masking patterns (like STEAM_ACC) if not blocked
    if [[ "$blocked" == false ]]; then
        for pattern in "${!CONTAINS_MASK[@]}"; do
            if [[ $modified_line == *"$pattern"* ]]; then
                modified_line=${modified_line//$pattern/${CONTAINS_MASK[$pattern]}}
            fi
        done
    fi

    # Output or log blocked message
    if [[ "$blocked" == true ]]; then
        if [[ "${FILTER_PREVIEW_MODE:-false}" == "true" ]]; then
            log_message "Blocked message: $line" "debug"
        fi
    else
        printf '%s\n' "$modified_line"
    fi
}