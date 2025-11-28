#!/bin/bash
# Common utility functions for all updater scripts

# Configuration
VERSION_FILE="${EGG_DIR:-/home/container/egg}/versions.txt"

# Get GitHub release info (supports prerelease via PRERELEASE env var)
# Outputs JSON: {version, asset_url, asset_name, is_prerelease}
get_github_release() {
    local repo="$1"
    local asset_pattern="${2:-.*}"
    local url="https://api.github.com/repos/$repo/releases"

    # Select endpoint based on prerelease setting (log to stderr to not pollute output)
    if [ "${PRERELEASE:-0}" = "1" ]; then
        log_message "Checking releases (prereleases enabled) for $repo" "debug" >&2
    else
        url="$url/latest"
        log_message "Checking latest stable release for $repo" "debug" >&2
    fi

    curl -s "$url" 2>/dev/null | jq --arg p "$asset_pattern" '
        (if type == "array" then .[0] else . end) //empty |
        {
            version: .tag_name,
            is_prerelease: .prerelease,
            asset_url: (first(.assets[] | select(.name | test($p)) | .browser_download_url) // ""),
            asset_name: (first(.assets[] | select(.name | test($p)) | .name) // "")
        }
    ' 2>/dev/null
}

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

# Add addon path to gameinfo.gi if not already present
# Inserts addons between "Game_LowViolence csgo_lv" and "Game csgo" lines
# Usage: add_to_gameinfo "csgo/addons/metamod"
add_to_gameinfo() {
    local addon_path="$1"
    local GAMEINFO_FILE="/home/container/game/csgo/gameinfo.gi"

    if [ ! -f "$GAMEINFO_FILE" ]; then
        log_message "gameinfo.gi not found at $GAMEINFO_FILE" "error"
        return 1
    fi

    # Check if path already exists
    if grep -q "Game[[:blank:]]*${addon_path}" "$GAMEINFO_FILE"; then
        log_message "${addon_path} already in gameinfo.gi" "debug"
        return 0
    fi

    log_message "Adding ${addon_path} to gameinfo.gi..." "info"

    # Create backup
    cp "$GAMEINFO_FILE" "$GAMEINFO_FILE.bak" 2>/dev/null || {
        log_message "Failed to backup gameinfo.gi" "error"
        return 1
    }

    # Insert addon after "Game_LowViolence" line using sed
    # This ensures addons are grouped together after LV line, with empty line before "Game csgo"
    sed "/Game_LowViolence/a\\
            Game    ${addon_path}" "$GAMEINFO_FILE.bak" > "$GAMEINFO_FILE"

    if [ $? -ne 0 ]; then
        log_message "sed command failed, restoring backup" "error"
        mv "$GAMEINFO_FILE.bak" "$GAMEINFO_FILE"
        return 1
    fi

    # Verify it was actually added
    if grep -q "Game[[:space:]]*${addon_path}" "$GAMEINFO_FILE"; then
        log_message "Added ${addon_path} to gameinfo.gi" "info"
        rm -f "$GAMEINFO_FILE.bak"
        return 0
    else
        log_message "WARNING: ${addon_path} not found after sed insertion, restoring backup" "error"
        mv "$GAMEINFO_FILE.bak" "$GAMEINFO_FILE"
        return 1
    fi
}

# Remove addon path from gameinfo.gi if present
# Usage: remove_from_gameinfo "sharp"
remove_from_gameinfo() {
    local addon_path="$1"
    local GAMEINFO_FILE="/home/container/game/csgo/gameinfo.gi"

    if [ ! -f "$GAMEINFO_FILE" ]; then
        log_message "gameinfo.gi not found at $GAMEINFO_FILE" "debug"
        return 0
    fi

    # Check if path exists
    if ! grep -q "Game[[:blank:]]*${addon_path}" "$GAMEINFO_FILE"; then
        log_message "${addon_path} not found in gameinfo.gi" "debug"
        return 0
    fi

    log_message "Removing ${addon_path} from gameinfo.gi..." "info"

    # Create backup
    cp "$GAMEINFO_FILE" "$GAMEINFO_FILE.bak" 2>/dev/null || {
        log_message "Failed to backup gameinfo.gi" "error"
        return 1
    }

    # Remove the line containing the addon path
    sed "/Game[[:space:]]*${addon_path//\//\\/}/d" "$GAMEINFO_FILE.bak" > "$GAMEINFO_FILE"

    if [ $? -ne 0 ]; then
        log_message "sed command failed, restoring backup" "error"
        mv "$GAMEINFO_FILE.bak" "$GAMEINFO_FILE"
        return 1
    fi

    # Verify it was removed
    if ! grep -q "Game[[:space:]]*${addon_path}" "$GAMEINFO_FILE"; then
        log_message "Removed ${addon_path} from gameinfo.gi" "info"
        rm -f "$GAMEINFO_FILE.bak"
        return 0
    else
        log_message "Failed to remove ${addon_path}, restoring backup" "error"
        mv "$GAMEINFO_FILE.bak" "$GAMEINFO_FILE"
        return 1
    fi
}

# Ensure MetaMod is always first addon after Game_LowViolence line
# This is critical because MetaMod must load before others as for example SwiftlyS2 if loaded first, metamod cant load
ensure_metamod_first() {
    local GAMEINFO_FILE="/home/container/game/csgo/gameinfo.gi"

    # Check if metamod exists in file
    if ! grep -q "Game.*csgo/addons/metamod" "$GAMEINFO_FILE"; then
        return 0  # No metamod, nothing to reorder
    fi

    # Get line numbers
    local lv_line=$(grep -n "Game_LowViolence" "$GAMEINFO_FILE" | head -n1 | cut -d: -f1)
    local metamod_line=$(grep -n "Game.*csgo/addons/metamod" "$GAMEINFO_FILE" | head -n1 | cut -d: -f1)

    # Check if there are any Game lines between LV and MetaMod
    local has_addons_before=false
    local line_num=$((lv_line + 1))
    while [ $line_num -lt $metamod_line ]; do
        if sed -n "${line_num}p" "$GAMEINFO_FILE" | grep -q "^[[:space:]]*Game[[:space:]]"; then
            has_addons_before=true
            break
        fi
        ((line_num++))
    done

    # If metamod is already first (no Game lines between LV and metamod), done
    if [ "$has_addons_before" = false ]; then
        log_message "MetaMod already in correct position" "debug"
        return 0
    fi

    log_message "Repositioning MetaMod to first position after LowViolence..." "info"

    # Backup
    cp "$GAMEINFO_FILE" "$GAMEINFO_FILE.bak" 2>/dev/null || {
        log_message "Failed to backup gameinfo.gi" "error"
        return 1
    }

    # Remove metamod line wherever it is
    sed '/Game.*csgo\/addons\/metamod/d' "$GAMEINFO_FILE.bak" > "$GAMEINFO_FILE.tmp"

    # Insert metamod right after LowViolence line
    sed '/Game_LowViolence/a\            Game    csgo/addons/metamod' "$GAMEINFO_FILE.tmp" > "$GAMEINFO_FILE"

    # Cleanup temp file
    rm -f "$GAMEINFO_FILE.tmp"

    # Verify
    if grep -q "Game.*csgo/addons/metamod" "$GAMEINFO_FILE"; then
        log_message "MetaMod repositioned successfully" "info"
        rm -f "$GAMEINFO_FILE.bak"
        return 0
    else
        log_message "Failed to reposition MetaMod, restoring backup" "error"
        mv "$GAMEINFO_FILE.bak" "$GAMEINFO_FILE"
        return 1
    fi
}

# Patch RequireLoginForDedicatedServers setting based on ALLOW_TOKENLESS variable
# If ALLOW_TOKENLESS=1 → sets to 0 (allows tokenless)
# If ALLOW_TOKENLESS=0 → sets to 1 (requires token)
patch_tokenless_setting() {
    local GAMEINFO_FILE="/home/container/game/csgo/gameinfo.gi"

    if [ ! -f "$GAMEINFO_FILE" ]; then
        log_message "gameinfo.gi not found, skipping tokenless patch" "debug"
        return 0
    fi

    # Determine desired value based on ALLOW_TOKENLESS variable
    local desired_value
    if [ "${ALLOW_TOKENLESS:-0}" -eq 1 ]; then
        desired_value="0"  # Allow tokenless
    else
        desired_value="1"  # Require token
    fi

    # Check current value
    local current_value=$(grep -oP 'RequireLoginForDedicatedServers"\s+"\K[0-9]+' "$GAMEINFO_FILE" 2>/dev/null)

    # If already correct, skip
    if [ "$current_value" = "$desired_value" ]; then
        log_message "RequireLoginForDedicatedServers already set to $desired_value" "debug"
        return 0
    fi

    # Backup
    cp "$GAMEINFO_FILE" "$GAMEINFO_FILE.bak" 2>/dev/null || {
        log_message "Failed to backup gameinfo.gi" "error"
        return 1
    }

    # Patch the value
    sed -i "s/\(RequireLoginForDedicatedServers\"[[:space:]]*\)\"[0-9]\"/\1\"$desired_value\"/" "$GAMEINFO_FILE"

    # Verify change
    local new_value=$(grep -oP 'RequireLoginForDedicatedServers"\s+"\K[0-9]+' "$GAMEINFO_FILE" 2>/dev/null)
    if [ "$new_value" = "$desired_value" ]; then
        rm -f "$GAMEINFO_FILE.bak"
        return 0
    else
        log_message "Failed to patch RequireLoginForDedicatedServers, restoring backup" "error"
        mv "$GAMEINFO_FILE.bak" "$GAMEINFO_FILE"
        return 1
    fi
}
