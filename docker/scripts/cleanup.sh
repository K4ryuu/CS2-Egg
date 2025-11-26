#!/bin/bash
source /utils/logging.sh

# Cache platform detection for stat command (performance optimization)
STAT_PLATFORM=$(uname -s)
if [[ "$STAT_PLATFORM" == "Darwin" ]]; then
    STAT_CMD="stat -f %z"
else
    STAT_CMD="stat -c %s"
fi

# Quick check to make sure we have enough disk space
check_filesystem() {
    local dir="$1"
    local required_space=1048576  # 1GB in KB

    # Get filesystem info safely
    local fs_info
    if ! fs_info=$(df -k "$dir" 2>/dev/null | tail -n 1); then
        log_message "Failed to get filesystem information for $dir" "error"
        return 1
    fi

    # Parse available space safely
    local available
    available=$(echo "$fs_info" | awk '{print $4}')
    if [[ ! "$available" =~ ^[0-9]+$ ]]; then
        log_message "Invalid filesystem information received" "error"
        return 1
    fi

    if [ "$available" -lt "$required_space" ]; then
        log_message "Low disk space warning: Less than 1GB available" "warning"
    fi

    return 0
}

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
    # Grab config values (already loaded by config.sh)
    local GAME_DIRECTORY="${CLEANUP_GAME_DIR:-./game/csgo}"
    local BACKUP_ROUND_PURGE_INTERVAL="${CLEANUP_BACKUP_HOURS:-24}"
    local DEMO_PURGE_INTERVAL="${CLEANUP_DEMOS_HOURS:-168}"
    local CSS_JUNK_PURGE_INTERVAL="${CLEANUP_LOGS_HOURS:-72}"
    local ACCELERATOR_DUMP_PURGE_INTERVAL="${CLEANUP_DUMPS_HOURS:-168}"
    local ACCELERATOR_DUMPS_DIR="${CLEANUP_DUMPS_DIR:-./game/csgo/addons/AcceleratorCS2/dumps}"

    # Make sure the game dir actually exists
    if [ ! -d "$GAME_DIRECTORY" ]; then
        log_message "Game directory not found: $GAME_DIRECTORY" "error"
        return 1
    fi

    # Check filesystem before proceeding
    if ! check_filesystem "$GAME_DIRECTORY"; then
        log_message "Filesystem check failed" "error"
        return 1
    fi

    # Track how much stuff we delete
    declare -A stats=(
        ["backup_rounds"]=0
        ["demos"]=0
        ["css_logs"]=0
        ["swiftly_logs"]=0
        ["accelerator_logs"]=0
        ["accelerator_dumps"]=0
    )

    local start_time
    start_time=$(date +%s)
    local total_size=0
    local deleted_count=0

    # Enhanced log deletion function with error handling
    log_deletion() {
        local file="$1"
        local category="$2"

        if [ ! -f "$file" ]; then
            log_message "File not found: $file" "warning"
            return 1
        fi

        local size
        size=$($STAT_CMD "$file" 2>/dev/null)

        if [ $? -ne 0 ] || [[ ! "$size" =~ ^[0-9]+$ ]]; then
            log_message "Failed to get file size for: $file" "warning"
            size=0
        fi

        if rm -f "$file"; then
            total_size=$((total_size + size))
            ((stats[$category]++))
            ((deleted_count++))
        else
            log_message "Failed to delete: $file" "error"
        fi
    }

    # Process files with error handling
    while IFS= read -r -d '' file; do
        if [[ "$file" == *"backup_round"* ]]; then
            log_deletion "$file" "backup_rounds"
        elif [[ "$file" == *.dem ]]; then
            log_deletion "$file" "demos"
        elif [[ "$file" == */addons/counterstrikesharp/logs/* ]]; then
            log_deletion "$file" "css_logs"
        elif [[ "$file" == */addons/swiftlys2/logs/* ]]; then
            log_deletion "$file" "swiftly_logs"
        fi
    done < <(find "$GAME_DIRECTORY" \( \
        -name "backup_round*.txt" -mmin "+$((BACKUP_ROUND_PURGE_INTERVAL*60))" -o \
        -name "*.dem" -mmin "+$((DEMO_PURGE_INTERVAL*60))" -o \
        \( -path "*/addons/counterstrikesharp/logs/*.txt" -mmin "+$((CSS_JUNK_PURGE_INTERVAL*60))" \) -o \
        \( -path "*/addons/swiftlys2/logs/*.log" -mmin "+$((CSS_JUNK_PURGE_INTERVAL*60))" \) \
        \) -print0 2>/dev/null)

    # Handle Accelerator logs with proper error checking
    if [ -d "$ACCELERATOR_DUMPS_DIR" ]; then
        while IFS= read -r -d '' file; do
            if [[ "$file" == *.dmp.txt ]]; then
                log_deletion "$file" "accelerator_logs"
            else
                log_deletion "$file" "accelerator_dumps"
            fi
        done < <(find "$ACCELERATOR_DUMPS_DIR" \( \
            -name "*.dmp.txt" -o \
            -name "*.dmp" \
            \) -mmin "+$((ACCELERATOR_DUMP_PURGE_INTERVAL*60))" -print0 2>/dev/null)
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Final status report
    if ((deleted_count > 0)); then
        log_message "Cleaned up $deleted_count file(s), freed $(format_size "$total_size") in ${duration}s" "success"
        for category in "${!stats[@]}"; do
            if ((stats[$category] > 0)); then
                log_message "  ${category}: ${stats[$category]} file(s)" "debug"
            fi
        done
    fi

    return 0
}