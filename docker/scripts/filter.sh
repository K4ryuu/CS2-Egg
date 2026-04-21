#!/bin/bash

source /utils/logging.sh
source /utils/config.sh

# Universal secret masker
mask_secrets() {
    local text="$1"
    if [ -n "${STEAM_ACC:-}" ] && [[ "$text" == *"${STEAM_ACC}"* ]]; then
        local mask
        mask=$(printf '%*s' "${#STEAM_ACC}" '' | tr ' ' '*')
        text="${text//${STEAM_ACC}/$mask}"
    fi
    printf '%s' "$text"
}

setup_message_filter() {
    # Pattern filter is opt-in via ENABLE_FILTER. Secret masking is always on
    declare -gA EXACT_PATTERNS=()
    declare -gA CONTAINS_BLOCK=()

    if [ "${ENABLE_FILTER:-0}" -ne 1 ]; then
        return 0
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

    if [[ -z "$line" ]]; then
        printf '%s\n' "$line"
        return
    fi

    # Mask secrets always (STEAM_ACC etc.) — independent of ENABLE_FILTER.
    line="$(mask_secrets "$line")"

    # Pattern-based blocking is opt-in.
    if [ "${ENABLE_FILTER:-0}" -eq 1 ]; then
        if [[ -n "${EXACT_PATTERNS[$line]}" ]]; then
            if [[ "${FILTER_PREVIEW_MODE:-false}" == "true" ]]; then
                log_message "Blocked message: $line" "debug"
            fi
            return
        fi
        for pattern in "${!CONTAINS_BLOCK[@]}"; do
            if [[ $line == *"$pattern"* ]]; then
                if [[ "${FILTER_PREVIEW_MODE:-false}" == "true" ]]; then
                    log_message "Blocked message: $line" "debug"
                fi
                return
            fi
        done
    fi

    printf '%s\n' "$line"
}