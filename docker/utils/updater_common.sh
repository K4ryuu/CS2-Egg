#!/bin/bash
# Common utility functions for all updater scripts

# Configuration
VERSION_FILE="${EGG_DIR:-/home/container/egg}/versions.txt"

# Get current version from version file
get_current_version() {
    local addon="$1"
    if [ -f "$VERSION_FILE" ]; then
        grep "^$addon=" "$VERSION_FILE" | cut -d'=' -f2
    else
        echo ""
    fi
}

# Update version file
update_version_file() {
    local addon="$1"
    local new_version="$2"

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$VERSION_FILE")"

    if [ -f "$VERSION_FILE" ] && grep -q "^$addon=" "$VERSION_FILE"; then
        sed -i "s/^$addon=.*/$addon=$new_version/" "$VERSION_FILE"
    else
        echo "$addon=$new_version" >> "$VERSION_FILE"
    fi
}

# Centralized download and extract function
handle_download_and_extract() {
    local url="$1"
    local output_file="$2"
    local extract_dir="$3"
    local file_type="$4"  # "zip" or "tar.gz"

    log_message "Downloading from: $url" "debug"

    # Download with timeout and retry
    local max_retries=3
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -fsSL -m 300 -o "$output_file" "$url"; then
            break
        fi
        ((retry++))
        log_message "Download failed (attempt $retry/$max_retries)" "warning"
        sleep 5
    done

    if [ $retry -eq $max_retries ]; then
        log_message "Failed to download after $max_retries attempts" "error"
        return 1
    fi

    if [ ! -s "$output_file" ]; then
        log_message "Downloaded file is empty" "error"
        return 1
    fi

    mkdir -p "$extract_dir"

    case $file_type in
        "zip")
            unzip -qq -o "$output_file" -d "$extract_dir" || {
                log_message "Failed to extract zip file" "error"
                return 1
            }
            ;;
        "tar.gz")
            tar -xzf "$output_file" -C "$extract_dir" || {
                log_message "Failed to extract tar.gz file" "error"
                return 1
            }
            ;;
    esac

    return 0
}

# Centralized version checking
check_version() {
    local addon="$1"
    local current="${2:-none}"
    local new="$3"

    if [ "$current" != "$new" ]; then
        log_message "Update available for $addon: $new (current: $current)" "info"
        return 0
    fi

    log_message "$addon is up-to-date ($current)" "debug"
    return 1
}
