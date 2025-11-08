#!/bin/bash
source /utils/logging.sh

setup_version_check_cron() {
    if [ "${UPDATE_AUTO_RESTART:-0}" -ne 1 ]; then
        log_message "Auto-restart is disabled, skipping cron setup" "debug"
        return 0
    fi
    
    # Make sure cron is actually installed
    if ! command -v cron &> /dev/null; then
        log_message "Cron is not installed, falling back to script-based checking" "warning"
        return 1
    fi
    
    # Figure out how often to check (in minutes)
    local check_interval="${VERSION_CHECK_INTERVAL:-60}"
    
    # Build the cron schedule based on interval
    local cron_schedule
    if [ "$check_interval" -lt 60 ]; then
        cron_schedule="*/$check_interval * * * *"
    else
        local hours=$((check_interval / 60))
        if [ "$hours" -gt 0 ]; then
            cron_schedule="0 */$hours * * *"
        else
            cron_schedule="*/60 * * * *"
        fi
    fi
    
    # Add the cron job
    (crontab -l 2>/dev/null; echo "$cron_schedule /scripts/check-updates.sh --once >> /var/log/cs2_update_check.log 2>&1") | crontab -
    
    log_message "Cron job set up for version checking every $check_interval minutes" "success"
    
    # Start cron service (different commands for different distros)
    service cron start 2>/dev/null || cron 2>/dev/null || crond 2>/dev/null
    
    return 0
}

# Export so other scripts can use this
export -f setup_version_check_cron