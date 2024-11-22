#!/bin/bash
source /utils/logging.sh

format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        printf "%.2f GB" $(echo "scale=2; $size/1073741824" | bc)
    elif [ $size -ge 1048576 ]; then
        printf "%.2f MB" $(echo "scale=2; $size/1048576" | bc)
    elif [ $size -ge 1024 ]; then
        printf "%.2f KB" $(echo "scale=2; $size/1024" | bc)
    else
        printf "%d B" $size
    fi
}

cleanup() {
    log_message "Starting cleanup..." "running"

    # Configuration
    local BACKUP_ROUND_PURGE_INTERVAL=24
    local DEMO_PURGE_INTERVAL=168
    local CSS_JUNK_PURGE_INTERVAL=72
    local ACCELERATOR_DUMP_PURGE_INTERVAL=168
    local ACCELERATOR_DUMPS_DIR="$OUTPUT_DIR/AcceleratorCS2/dumps"

    # Statistics for debug
    declare -A stats=(
        ["backup_rounds"]=0
        ["demos"]=0
        ["css_logs"]=0
        ["accelerator_logs"]=0
        ["accelerator_dumps"]=0
    )

    local start_time=$(date +%s)
    local total_size=0
    local deleted_count=0

    # Function to log file deletion with size
    log_deletion() {
        local file="$1"
        local category="$2"
        local size=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)
        total_size=$((total_size + size))
        ((stats[$category]++))
        ((deleted_count++))
        log_message "Deleted ${category}: ${file##*/} ($(format_size $size))" "debug"
    }

    # Find and delete old files
    while IFS= read -r -d '' file; do
        if [[ $file == *"backup_round"* ]]; then
            log_deletion "$file" "backup_rounds"
        elif [[ $file == *.dem ]]; then
            log_deletion "$file" "demos"
        elif [[ $file == */addons/counterstrikesharp/logs/* ]]; then
            log_deletion "$file" "css_logs"
        fi
        rm -f "$file"
    done < <(find "$GAME_DIRECTORY" \( \
        -name "backup_round*.txt" -mmin +$((BACKUP_ROUND_PURGE_INTERVAL*60)) -o \
        -name "*.dem" -mmin +$((DEMO_PURGE_INTERVAL*60)) -o \
        \( -path "*/addons/counterstrikesharp/logs/*.txt" -mmin +$((CSS_JUNK_PURGE_INTERVAL*60)) \) \
        \) -print0)

    # Handle Accelerator logs separately only if directory exists
    if [ -d "$ACCELERATOR_DUMPS_DIR" ]; then
        while IFS= read -r -d '' file; do
            if [[ $file == *.dmp.txt ]]; then
                log_deletion "$file" "accelerator_logs"
            else
                log_deletion "$file" "accelerator_dumps"
            fi
            rm -f "$file"
        done < <(find "$ACCELERATOR_DUMPS_DIR" \( \
            -name "*.dmp.txt" -o \
            -name "*.dmp" \
            \) -mmin +$((ACCELERATOR_DUMP_PURGE_INTERVAL*60)) -print0)
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if ((deleted_count > 0)); then
        log_message "Cleanup completed successfully! Freed $(format_size $total_size) across $deleted_count files in $duration seconds." "success"
    else
        log_message "Cleanup completed. No files were deleted." "success"
    fi
}