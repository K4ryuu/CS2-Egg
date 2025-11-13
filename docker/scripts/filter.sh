#!/bin/bash

source /utils/logging.sh
source /utils/config.sh

setup_message_filter() {
    if [ "${ENABLE_FILTER:-0}" -ne 1 ]; then
        return 0
    fi

    declare -gA EXACT_PATTERNS=()
    declare -gA CONTAINS_PATTERNS=()

    if [ -n "${STEAM_ACC}" ]; then
        local mask=$(printf '%*s' "${#STEAM_ACC}" '' | tr ' ' '*')
        CONTAINS_PATTERNS["${STEAM_ACC}"]="$mask"
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
                CONTAINS_PATTERNS["$pattern"]="1"
            fi
            ((pattern_count++))
        done <<< "$patterns"
    fi

    log_message "Console filter active: $pattern_count patterns (${#EXACT_PATTERNS[@]} exact, ${#CONTAINS_PATTERNS[@]} contains)" "info"
}

handle_server_output() {
    local line="$1"

    [[ -z "$line" ]] && {
        printf '%s\n' "$line"
        return
    }

    if [ "${ENABLE_FILTER:-0}" -ne 1 ]; then
        printf '%s\n' "$line"
        return
    fi

    local blocked=false
    local modified_line="$line"

    for pattern in "${!EXACT_PATTERNS[@]}"; do
        if [[ "$line" == "$pattern" ]]; then
            blocked=true
            break
        fi
    done

    if [[ "$blocked" == false ]]; then
        for pattern in "${!CONTAINS_PATTERNS[@]}"; do
            if [[ $line == *"$pattern"* ]]; then
                if [ -n "${CONTAINS_PATTERNS[$pattern]}" ] && [ "${CONTAINS_PATTERNS[$pattern]}" != "1" ]; then
                    modified_line=${modified_line//$pattern/${CONTAINS_PATTERNS[$pattern]}}
                else
                    blocked=true
                    break
                fi
            fi
        done
    fi

    if [[ "$blocked" == true ]]; then
        if [[ "${FILTER_PREVIEW_MODE:-false}" == "true" ]]; then
            log_message "Blocked message: $line" "debug"
        fi
    else
        printf '%s\n' "$modified_line"
    fi
}