#!/bin/bash
source /utils/logging.sh

is_file_older_than() {
    local file="$1"
    local hours="$2"
    local current_time=$(date +%s)
    local file_time=$(date -r "$file" +%s)
    local age=$(( (current_time - file_time) / 3600 ))
    [ "$age" -gt "$hours" ]
}

safe_delete() {
    local file="$1"
    local category="$2"
    rm -f "$file"
    log_message "Deleted $category file: $file" "success"
}

purge_files() {
    local directory="$1"
    local pattern="$2"
    local interval="$3"
    local category="$4"
    local count=0

    if [ -d "$directory" ]; then
        local files=$(find "$directory" -maxdepth 1 -type f -name "$pattern")
        for file in $files; do
            if [ -f "$file" ] && is_file_older_than "$file" "$interval"; then
                safe_delete "$file" "$category"
                ((count++))
            fi
        done
    fi

    if [ "$count" -gt 0 ]; then
        log_message "Deleted $count files in category: $category" "success"
    fi
}

cleanup() {
    if [ "$CLEANUP_ENABLED" = "1" ]; then
        log_message "Starting cleanup..." "running"

        GAME_DIRECTORY="./game/csgo"
        OUTPUT_DIR="./game/csgo/addons"
        TEMP_DIR="./temps"
        LOG_FILE="./game/startup_log.txt"
        VERSION_FILE="./game/versions.txt"

        rm -f "$LOG_FILE"

        BACKUP_ROUND_PURGE_INTERVAL=24
        DEMO_PURGE_INTERVAL=168
        CSS_JUNK_PURGE_INTERVAL=72
        ACCELERATOR_DUMPS_DIR="$OUTPUT_DIR/AcceleratorCS2/dumps"
        ACCELERATOR_DUMP_PURGE_INTERVAL=168

        mkdir -p "$TEMP_DIR"

        purge_files "$GAME_DIRECTORY" "backup_round*.txt" $BACKUP_ROUND_PURGE_INTERVAL "Logs"
        purge_files "$GAME_DIRECTORY" "*.dem" $DEMO_PURGE_INTERVAL "Demos"
        purge_files "$GAME_DIRECTORY/addons/counterstrikesharp/logs" "*.txt" $CSS_JUNK_PURGE_INTERVAL "CSS Logs"

        if [ -d "$ACCELERATOR_DUMPS_DIR" ]; then
            purge_files "$ACCELERATOR_DUMPS_DIR" "*.dmp.txt" $ACCELERATOR_DUMP_PURGE_INTERVAL "Accelerator Logs"
            purge_files "$ACCELERATOR_DUMPS_DIR" "*.dmp" $ACCELERATOR_DUMP_PURGE_INTERVAL "Accelerator Dumps"
        fi

        log_message "Cleanup completed." "success"
    fi
}