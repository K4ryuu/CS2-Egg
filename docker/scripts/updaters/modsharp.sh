#!/bin/bash
# ModSharp Auto-Update Script
# Handles .NET 10 runtime and ModSharp installation/updates

source /utils/logging.sh
source /utils/updater_common.sh

# Configuration
MODSHARP_DIR="/home/container/game/sharp"
DOTNET_VERSION="10.0.0"
CONFIG_BACKUP="$TEMP_DIR/core.json.backup"

# Install or update .NET runtime
install_dotnet_runtime() {
    local runtime_dir="$MODSHARP_DIR/runtime"
    local dotnet_version="$DOTNET_VERSION"
    local current_dotnet_version=$(get_current_version "DotNet")

    # Check if runtime is up to date
    if [ "$current_dotnet_version" = "$dotnet_version" ] && [ -f "$runtime_dir/dotnet" ]; then
        log_message ".NET runtime already up to date: $dotnet_version" "debug"
        return 0
    fi

    log_message "Installing .NET $dotnet_version runtime..." "running"

    # Create runtime directory
    mkdir -p "$runtime_dir"

    # Download and extract using common utility
    local dotnet_url="https://dotnetcli.azureedge.net/dotnet/Runtime/$dotnet_version/dotnet-runtime-$dotnet_version-linux-x64.tar.gz"
    local download_file="$TEMP_DIR/dotnet-runtime.tar.gz"

    if handle_download_and_extract "$dotnet_url" "$download_file" "$runtime_dir" "tar.gz"; then
        update_version_file "DotNet" "$dotnet_version"
        log_message ".NET $dotnet_version runtime installed successfully" "success"
        rm -f "$download_file"
        return 0
    else
        log_message "Failed to install .NET runtime" "error"
        rm -f "$download_file"
        return 1
    fi
}

# Download and extract asset (uses common utility)
download_and_extract() {
    local url="$1"
    local target_dir="$2"
    local download_file="$TEMP_DIR/$(basename "$url")"

    handle_download_and_extract "$url" "$download_file" "$target_dir" "zip"
    local result=$?

    rm -f "$download_file"
    return $result
}

# Main update function
update_modsharp() {
    # Step 1: Install/update .NET runtime
    if ! install_dotnet_runtime; then
        log_message "Failed to install .NET runtime, aborting ModSharp update" "error"
        return 1
    fi

    # Step 2: Get release info (direct API call for multiple assets)
    local repo="Kxnrl/modsharp-public"
    local api_url="https://api.github.com/repos/$repo/releases"
    local release_info

    if [ "${PRERELEASE:-0}" -eq 1 ]; then
        release_info=$(curl -s "$api_url" | jq '.[0] // empty')
    else
        release_info=$(curl -s "$api_url/latest")
    fi

    if [ -z "$release_info" ] || ! echo "$release_info" | jq -e . >/dev/null 2>&1; then
        log_message "Failed to get ModSharp release info" "error"
        return 1
    fi

    # Extract version and asset URLs (using GitHub API format)
    local latest_version=$(echo "$release_info" | jq -r '.tag_name // empty' | sed 's/-//g')
    local core_url=$(echo "$release_info" | jq -r '.assets[] | select(.name | contains("linux.zip") and (contains("extensions") | not)) | .browser_download_url')
    local extensions_url=$(echo "$release_info" | jq -r '.assets[] | select(.name | contains("linux-extensions.zip")) | .browser_download_url')

    if [ -z "$latest_version" ] || [ -z "$core_url" ] || [ -z "$extensions_url" ]; then
        log_message "Could not parse ModSharp release data" "error"
        return 1
    fi

    # Check if update needed
    local current_version=$(get_current_version "ModSharp")
    log_message "Current version: ${current_version:-none}" "debug"
    log_message "Latest version: $latest_version" "debug"

    # Check if update is needed
    if [ -n "$current_version" ]; then
        semver_compare "$latest_version" "$current_version"
        case $? in
            0) # Equal
                log_message "ModSharp is up-to-date ($current_version)" "info"
                return 0
                ;;
            2) # new < current
                log_message "ModSharp is at a newer version ($current_version) than latest ($latest_version). Skipping downgrade." "info"
                return 0
                ;;
        esac
    fi

    log_message "Update available: $latest_version (current: ${current_version:-none})" "info"

    # Step 3: Backup core.json if exists
    if [ -f "$MODSHARP_DIR/configs/core.json" ]; then
        cp "$MODSHARP_DIR/configs/core.json" "$CONFIG_BACKUP"
        log_message "Backed up core.json" "debug"
    fi

    # Step 4: Download and install core (extract to /game/)
    if ! download_and_extract "$core_url" "./game/"; then
        log_message "Failed to install ModSharp core" "error"
        return 1
    fi

    # Step 5: Download and install extensions (extract to /game/sharp/shared/)
    if ! download_and_extract "$extensions_url" "./game/sharp/shared/"; then
        log_message "Failed to install ModSharp extensions" "warning"
        # Continue anyway, extensions are not critical
    fi

    # Step 6: Restore core.json if we backed it up
    if [ -f "$CONFIG_BACKUP" ]; then
        mkdir -p "$MODSHARP_DIR/configs"
        cp "$CONFIG_BACKUP" "$MODSHARP_DIR/configs/core.json"
        log_message "Restored core.json config" "success"
        rm -f "$CONFIG_BACKUP"
    fi

    # Step 8: Update version file
    update_version_file "ModSharp" "$latest_version"

    log_message "ModSharp updated to $latest_version" "success"
    return 0
}

# Entry point
main() {
    # Create temp directory
    mkdir -p "$TEMP_DIR"

    # Install or update ModSharp
    update_modsharp

    local exit_code=$?

    # Cleanup temp directory
    rm -rf "$TEMP_DIR"

    return $exit_code
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
