#!/bin/bash
source /utils/logging.sh

# File system check function
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

# Improved size formatting function
format_size() {
    local size="$1"
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return 1
    fi

    if [ "$size" -ge 1073741824 ]; then
        printf "%.2f GB" "$(echo "scale=2; $size/1073741824" | bc)"
    elif [ "$size" -ge 1048576 ]; then
        printf "%.2f MB" "$(echo "scale=2; $size/1048576" | bc)"
    elif [ "$size" -ge 1024 ]; then
        printf "%.2f KB" "$(echo "scale=2; $size/1024" | bc)"
    else
        printf "%d B" "$size"
    fi
}

cleanup() {
    log_message "Starting cleanup..." "running"

    # Validate required variables
    if [ -z "$GAME_DIRECTORY" ]; then
        log_message "GAME_DIRECTORY is not set" "error"
        return 1
    fi

    if [ ! -d "$GAME_DIRECTORY" ]; then
        log_message "GAME_DIRECTORY does not exist: $GAME_DIRECTORY" "error"
        return 1
    fi

    # Check filesystem before proceeding
    if ! check_filesystem "$GAME_DIRECTORY"; then
        log_message "Filesystem check failed" "error"
        return 1
    fi

    # Configuration
    local BACKUP_ROUND_PURGE_INTERVAL=24
    local DEMO_PURGE_INTERVAL=168
    local CSS_JUNK_PURGE_INTERVAL=72
    local ACCELERATOR_DUMP_PURGE_INTERVAL=168
    local ACCELERATOR_DUMPS_DIR="${OUTPUT_DIR:-$GAME_DIRECTORY}/AcceleratorCS2/dumps"

    # Statistics for debug
    declare -A stats=(
        ["backup_rounds"]=0
        ["demos"]=0
        ["css_logs"]=0
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
        size=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)

        if [ $? -ne 0 ] || [[ ! "$size" =~ ^[0-9]+$ ]]; then
            log_message "Failed to get file size for: $file" "warning"
            size=0
        fi

        if rm -f "$file"; then
            total_size=$((total_size + size))
            ((stats[$category]++))
            ((deleted_count++))
            log_message "Deleted ${category}: ${file##*/} ($(format_size "$size"))" "debug"
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
        fi
    done < <(find "$GAME_DIRECTORY" \( \
        -name "backup_round*.txt" -mmin "+$((BACKUP_ROUND_PURGE_INTERVAL*60))" -o \
        -name "*.dem" -mmin "+$((DEMO_PURGE_INTERVAL*60))" -o \
        \( -path "*/addons/counterstrikesharp/logs/*.txt" -mmin "+$((CSS_JUNK_PURGE_INTERVAL*60))" \) \
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
        log_message "Cleanup completed successfully! Freed $(format_size "$total_size") across $deleted_count files in $duration seconds." "success"
        for category in "${!stats[@]}"; do
            if ((stats[$category] > 0)); then
                log_message "- $category: ${stats[$category]} files" "debug"
            fi
        done
    else
        log_message "Cleanup completed. No files were deleted." "success"
    fi

    return 0
}