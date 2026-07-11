#!/bin/bash
source /utils/logging.sh

# Make file sizes readable for humans
format_size() {
    local size="$1"
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return 1
    fi

    if [ "$size" -ge 1073741824 ]; then
        printf "%.2f GB" "$(awk "BEGIN {printf \"%.2f\", $size/1073741824}")"
    elif [ "$size" -ge 1048576 ]; then
        printf "%.2f MB" "$(awk "BEGIN {printf \"%.2f\", $size/1048576}")"
    elif [ "$size" -ge 1024 ]; then
        printf "%.2f KB" "$(awk "BEGIN {printf \"%.2f\", $size/1024}")"
    else
        printf "%d B" "$size"
    fi
}

cleanup() {
    local config_file="${EGG_CONFIGS_DIR:-/home/container/egg/configs}/cleanup.json"

    if [ ! -f "$config_file" ]; then
        log_message "Cleanup config missing at $config_file" "error"
        return 1
    fi

    local rule_count
    rule_count=$(jq '.rules | length // 0' "$config_file" 2>/dev/null)
    if [ -z "$rule_count" ] || [ "$rule_count" -eq 0 ]; then
        log_message "No cleanup rules defined in cleanup.json" "debug"
        return 0
    fi

    declare -A stats=()
    local start_time total_size deleted_count
    start_time=$(date +%s)
    total_size=0
    deleted_count=0

    log_deletion() {
        local file="$1"
        local category="$2"

        if [ ! -f "$file" ]; then
            return 1
        fi

        local size
        size=$(stat -c %s "$file" 2>/dev/null)
        if [ $? -ne 0 ] || [[ ! "$size" =~ ^[0-9]+$ ]]; then
            size=0
        fi

        if rm -f "$file"; then
            total_size=$((total_size + size))
            stats[$category]=$((${stats[$category]:-0} + 1))
            ((deleted_count++))
        else
            log_message "Failed to delete: $file" "error"
        fi
    }

    # Delete a matched file's whole parent directory (crash-report bundles etc.).
    # $3 is the rule's root dir, which must never be deleted itself.
    log_dir_deletion() {
        local file="$1"
        local category="$2"
        local rule_root="$3"
        # normalize trailing slashes: dirname never emits one, and a mismatch here
        # would defeat the root-protection compare below
        while [[ "$rule_root" == */ && "$rule_root" != "/" ]]; do rule_root="${rule_root%/}"; done
        local parent
        parent=$(dirname "$file")

        # Fall back to single-file delete when the parent is the rule root, or when
        # the parent has subdirectories (only leaf bundle dirs may be removed whole,
        # a stray file must never take out a folder that holds other bundles).
        if [ "$parent" = "$rule_root" ] || [ ! -d "$parent" ] || \
           [ -n "$(find "$parent" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null)" ]; then
            log_deletion "$file" "$category"
            return
        fi

        local dsize fcount
        dsize=$(du -sb "$parent" 2>/dev/null | cut -f1)
        [[ "$dsize" =~ ^[0-9]+$ ]] || dsize=0
        fcount=$(find "$parent" -type f 2>/dev/null | wc -l)

        if rm -rf "$parent" 2>/dev/null; then
            total_size=$((total_size + dsize))
            stats[$category]=$((${stats[$category]:-0} + fcount))
            deleted_count=$((deleted_count + fcount))
        else
            log_message "Failed to delete: $parent" "error"
        fi
    }

    local i
    for ((i = 0; i < rule_count; i++)); do
        local name enabled hours recursive
        name=$(jq -r ".rules[$i].name // empty" "$config_file")
        enabled=$(jq -r ".rules[$i].enabled // true" "$config_file")

        if [ -z "$name" ] || [ "$enabled" != "true" ]; then
            continue
        fi

        hours=$(jq -r ".rules[$i].hours // 0" "$config_file")
        recursive=$(jq -r ".rules[$i].recursive // true" "$config_file")
        local delete_parent_dir
        delete_parent_dir=$(jq -r ".rules[$i].delete_parent_dir // false" "$config_file")

        local -a dirs=() patterns=()
        mapfile -t dirs < <(jq -r ".rules[$i].directories[]?" "$config_file")
        mapfile -t patterns < <(jq -r ".rules[$i].patterns[]?" "$config_file")

        if [ ${#dirs[@]} -eq 0 ] || [ ${#patterns[@]} -eq 0 ]; then
            continue
        fi

        # Build `-name A -o -name B` expression for find
        local -a pat_expr=()
        local first=true
        local p
        for p in "${patterns[@]}"; do
            if $first; then
                first=false
            else
                pat_expr+=("-o")
            fi
            pat_expr+=("-name" "$p")
        done

        local dir
        for dir in "${dirs[@]}"; do
            if [ ! -d "$dir" ]; then
                continue
            fi

            local -a find_cmd=(find "$dir")
            if [ "$recursive" != "true" ]; then
                find_cmd+=(-maxdepth 1)
            fi
            find_cmd+=(-type f '(' "${pat_expr[@]}" ')')
            if [ "$hours" -gt 0 ]; then
                find_cmd+=(-mmin "+$((hours * 60))")
            fi
            find_cmd+=(-print0)

            while IFS= read -r -d '' file; do
                if [ "$delete_parent_dir" = "true" ]; then
                    log_dir_deletion "$file" "$name" "$dir"
                else
                    log_deletion "$file" "$name"
                fi
            done < <("${find_cmd[@]}" 2>/dev/null)
        done
    done

    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    if ((deleted_count > 0)); then
        log_message "Cleaned up $deleted_count file(s), freed $(format_size "$total_size") in ${duration}s" "success"
        local category
        for category in "${!stats[@]}"; do
            if ((stats[$category] > 0)); then
                log_message "  ${category}: ${stats[$category]} file(s)" "debug"
            fi
        done
    fi

    return 0
}