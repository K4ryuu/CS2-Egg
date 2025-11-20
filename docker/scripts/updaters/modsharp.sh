#!/bin/bash
# ModSharp Auto-Update Script
# Handles .NET 10 runtime and ModSharp installation/updates

source /utils/logging.sh
source /utils/updater_common.sh

# Configuration
MODSHARP_DIR="./game/sharp"
DOTNET_VERSION="10.0.0"
TEMP_DIR="./temps"

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

    # Download URL
    local dotnet_url="https://dotnetcli.azureedge.net/dotnet/Runtime/$dotnet_version/dotnet-runtime-$dotnet_version-linux-x64.tar.gz"
    local download_file="$TEMP_DIR/dotnet-runtime.tar.gz"

    log_message "Downloading from: $dotnet_url" "debug"

    # Download with retry logic
    local max_retries=3
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -fsSL -m 300 -o "$download_file" "$dotnet_url"; then
            break
        fi
        ((retry++))
        log_message "Download failed (attempt $retry/$max_retries)" "warning"
        sleep 5
    done

    if [ $retry -eq $max_retries ]; then
        log_message "Failed to download .NET runtime after $max_retries attempts" "error"
        return 1
    fi

    # Verify download
    if [ ! -s "$download_file" ]; then
        log_message "Downloaded .NET runtime file is empty" "error"
        return 1
    fi

    # Extract runtime
    log_message "Extracting .NET runtime..." "running"
    if tar -xzf "$download_file" -C "$runtime_dir" 2>/dev/null; then
        # Update version file
        update_version_file "DotNet" "$dotnet_version"

        log_message ".NET $dotnet_version runtime installed successfully" "success"
        rm -f "$download_file"
        return 0
    else
        log_message "Failed to extract .NET runtime" "error"
        rm -f "$download_file"
        return 1
    fi
}

# Get latest ModSharp version from GitHub Releases
get_latest_modsharp_version() {
    local api_url="https://api.github.com/repos/Kxnrl/modsharp-public/releases/latest"
    local response=$(curl -s "$api_url" 2>/dev/null)

    if [ -z "$response" ]; then
        log_message "Failed to fetch ModSharp releases" "error"
        return 1
    fi

    # Extract tag name (e.g., "git-69")
    local tag_name=$(echo "$response" | jq -r '.tag_name // empty')

    if [ -z "$tag_name" ]; then
        log_message "Could not parse ModSharp version from API response" "error"
        return 1
    fi

    # Convert "git-69" to "git69" for consistency
    echo "${tag_name//-/}"
}

# Download and extract ModSharp asset
download_modsharp_asset() {
    local asset_name="$1"
    local download_url="$2"
    local extract_to="$3"

    local download_file="$TEMP_DIR/${asset_name}"
    local extract_dir="$TEMP_DIR/extract_${asset_name%.zip}"

    log_message "Downloading $asset_name..." "running"

    # Download with retry
    local max_retries=3
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -fsSL -m 300 -o "$download_file" "$download_url"; then
            break
        fi
        ((retry++))
        log_message "Download failed (attempt $retry/$max_retries)" "warning"
        sleep 5
    done

    if [ $retry -eq $max_retries ]; then
        log_message "Failed to download $asset_name" "error"
        return 1
    fi

    # Verify download
    if [ ! -s "$download_file" ]; then
        log_message "Downloaded file is empty: $asset_name" "error"
        return 1
    fi

    # Extract
    log_message "Extracting $asset_name..." "running"
    mkdir -p "$extract_dir"

    if ! unzip -qq -o "$download_file" -d "$extract_dir" 2>/dev/null; then
        log_message "Failed to extract $asset_name" "error"
        rm -f "$download_file"
        return 1
    fi

    # Copy extracted files to target
    if [ -d "$extract_dir/build/linux/sharp" ]; then
        # Core asset structure: build/linux/sharp/
        log_message "Installing core files..." "debug"

        # Create directories first (preserve existing content)
        mkdir -p "$MODSHARP_DIR"/{bin,core,configs,gamedata,modules,shared,data,logs}

        # Copy from build/linux/sharp/ (only add new files, don't overwrite existing)
        local source_dir="$extract_dir/build/linux/sharp"

        cp -rn "$source_dir/bin"/* "$MODSHARP_DIR/bin/" 2>/dev/null || true
        cp -rn "$source_dir/core"/* "$MODSHARP_DIR/core/" 2>/dev/null || true
        cp -rn "$source_dir/gamedata"/* "$MODSHARP_DIR/gamedata/" 2>/dev/null || true
        cp -rn "$source_dir/shared"/* "$MODSHARP_DIR/shared/" 2>/dev/null || true
        cp -rn "$source_dir/modules"/* "$MODSHARP_DIR/modules/" 2>/dev/null || true

        # Only copy default config if it doesn't exist
        if [ ! -f "$MODSHARP_DIR/configs/core.json" ] && [ -f "$source_dir/configs/core.json" ]; then
            cp "$source_dir/configs/core.json" "$MODSHARP_DIR/configs/"
            log_message "Installed default core.json config" "debug"
        else
            log_message "Preserved existing core.json config" "debug"
        fi

        # Copy any other new config files (but don't overwrite existing)
        if [ -d "$source_dir/configs" ]; then
            cp -n "$source_dir/configs"/* "$MODSHARP_DIR/configs/" 2>/dev/null || true
        fi

    else
        # Extensions asset structure: build/linux-extensions/
        log_message "Installing extensions to shared/..." "debug"
        mkdir -p "$MODSHARP_DIR/shared"

        local extensions_dir="$extract_dir/build/linux-extensions"
        if [ -d "$extensions_dir" ]; then
            # Copy all extension folders (only add new files, don't overwrite existing)
            for item in "$extensions_dir"/*; do
                if [ -d "$item" ]; then
                    local folder_name=$(basename "$item")
                    cp -rn "$item" "$MODSHARP_DIR/shared/"
                    log_message "Installed extension: $folder_name" "debug"
                fi
            done
        fi
    fi

    # Cleanup
    rm -rf "$download_file" "$extract_dir"
    return 0
}

# Main update function
update_modsharp() {
    # Step 1: Install/update .NET runtime
    if ! install_dotnet_runtime; then
        log_message "Failed to install .NET runtime, aborting ModSharp update" "error"
        return 1
    fi

    # Step 2: Get latest version
    local latest_version=$(get_latest_modsharp_version)
    if [ -z "$latest_version" ]; then
        log_message "Could not determine latest ModSharp version" "error"
        return 1
    fi

    local current_version=$(get_current_version "ModSharp")

    log_message "Current version: ${current_version:-none}" "debug"
    log_message "Latest version: $latest_version" "debug"

    # Check if update needed
    if [ "$current_version" = "$latest_version" ] && [ -d "$MODSHARP_DIR" ]; then
        log_message "ModSharp is up-to-date ($current_version)" "info"
        return 0
    fi

    log_message "Update available: $latest_version (current: ${current_version:-none})" "info"

    # Step 3: Get release assets
    local api_url="https://api.github.com/repos/Kxnrl/modsharp-public/releases/latest"
    local response=$(curl -s "$api_url" 2>/dev/null)

    # Extract asset download URLs
    local core_url=$(echo "$response" | jq -r '.assets[] | select(.name | contains("linux.zip") and (contains("extensions") | not)) | .browser_download_url')
    local extensions_url=$(echo "$response" | jq -r '.assets[] | select(.name | contains("linux-extensions.zip")) | .browser_download_url')

    if [ -z "$core_url" ] || [ -z "$extensions_url" ]; then
        log_message "Could not find required assets in release" "error"
        return 1
    fi

    # Extract asset names
    local core_name=$(basename "$core_url")
    local extensions_name=$(basename "$extensions_url")

    log_message "Downloading ModSharp $latest_version..." "running"

    # Step 4: Download and install core
    if ! download_modsharp_asset "$core_name" "$core_url" "$MODSHARP_DIR"; then
        log_message "Failed to install ModSharp core" "error"
        return 1
    fi

    # Step 5: Download and install extensions
    if ! download_modsharp_asset "$extensions_name" "$extensions_url" "$MODSHARP_DIR/shared"; then
        log_message "Failed to install ModSharp extensions" "warning"
        # Continue anyway, extensions are not critical
    fi

    # Step 6: Update version file
    update_version_file "ModSharp" "$latest_version"

    log_message "ModSharp updated to $latest_version" "success"
    return 0
}

# Install ModSharp (first time)
install_modsharp() {
    update_modsharp
}

# Entry point
main() {
    # Create temp directory
    mkdir -p "$TEMP_DIR"

    # Check if installation or update is needed
    if [ ! -d "$MODSHARP_DIR" ]; then
        install_modsharp
    else
        update_modsharp
    fi

    local exit_code=$?

    # Cleanup temp directory
    rm -rf "$TEMP_DIR"

    return $exit_code
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
