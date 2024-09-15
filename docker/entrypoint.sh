#!/bin/bash
cd /home/container
sleep 1

# Colors for log messages using tput
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Prefix for logs
PREFIX="${RED}[KitsuneLab]${WHITE} > "

# Function to log messages with colors
log_message() {
  local message="$1"
  local type="$2"  # Type: running, error, success, debug

  # Strip any trailing newlines from the message
  message=$(echo -n "$message")

  case $type in
    running)
      printf "${PREFIX}${YELLOW}%s${NC}\n" "$message"
      ;;
    error)
      printf "${PREFIX}${RED}%s${NC}\n" "$message"
      ;;
    success)
      printf "${PREFIX}${GREEN}%s${NC}\n" "$message"
      ;;
    debug)
      printf "${PREFIX}${WHITE}[DEBUG] %s${NC}\n" "$message"
      ;;
    *)
      printf "${PREFIX}${WHITE}%s${NC}\n" "$message"
      ;;
  esac
}

# Function to handle errors based on exit codes and messages
handle_error() {
  local exit_code="$?"
  local last_command="$BASH_COMMAND"

  if [[ $exit_code -eq 127 ]]; then
    log_message "Command not found: $last_command" "error"
    log_message "Exit code: 127" "error"
  elif [[ $last_command == *"${GAMEROOT}/${GAMEEXE}"* ]]; then
    # This is the server shutdown, not an error
    log_message "Server has been shut down" "success"
  elif [[ $last_command != *"eval ${STEAMCMD}"* ]]; then
    log_message "Error occurred while executing: $last_command" "error"
    log_message "Exit code: $exit_code" "error"
  fi

  return $exit_code
}

# Set error handling trap
trap 'handle_error' ERR

# Make internal Docker IP address available to processes.
export INTERNAL_IP=`ip route get 1 | awk '{print $NF;exit}'`

# Update Source Server
if [ ! -z ${SRCDS_APPID} ]; then
    if [ ${SRCDS_STOP_UPDATE} -eq 0 ]; then
        STEAMCMD=""
        log_message "Starting SteamCMD for AppID: ${SRCDS_APPID}" "running"
        if [ ! -z ${SRCDS_BETAID} ]; then
            if [ ! -z ${SRCDS_BETAPASS} ]; then
                if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                    log_message "SteamCMD Validate Flag Enabled! Triggered install validation for AppID: ${SRCDS_APPID}" "running"
                    log_message "THIS MAY WIPE CUSTOM CONFIGURATIONS! Please stop the server if this was not intended." "error"
                    if [ ! -z ${SRCDS_LOGIN} ]; then
                        STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} validate +quit"
                    else
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} validate +quit"
                    fi
                else
                    if [ ! -z ${SRCDS_LOGIN} ]; then
                        STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} +quit"
                    else
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
                    fi
                fi
            else
                if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                    if [ ! -z ${SRCDS_LOGIN} ]; then
                        STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} validate +quit"
                    else
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} validate +quit"
                    fi
                else
                    if [ ! -z ${SRCDS_LOGIN} ]; then
                        STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
                    else
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
                    fi
                fi
            fi
        else
            if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                log_message "SteamCMD Validate Flag Enabled! Triggered install validation for AppID: ${SRCDS_APPID}" "running"
                log_message "THIS MAY WIPE CUSTOM CONFIGURATIONS! Please stop the server if this was not intended." "error"
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} validate +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} validate +quit"
                fi
            else
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} +quit"
                fi
            fi
        fi

        log_message "SteamCMD Launch: ${STEAMCMD}" "running"
        eval ${STEAMCMD}
        # Issue #44 - We can't symlink this, causes "File not found" errors. As a mitigation, copy over the updated binary on start.
        cp -f ./steamcmd/linux32/steamclient.so ./.steam/sdk32/steamclient.so
        cp -f ./steamcmd/linux64/steamclient.so ./.steam/sdk64/steamclient.so
    fi
fi

# Edit /home/container/game/csgo/gameinfo.gi to add MetaMod path
# Credit: https://github.com/ghostcap-gaming/ACMRS-cs2-metamod-update-fix/blob/main/acmrs.sh
GAMEINFO_FILE="/home/container/game/csgo/gameinfo.gi"
GAMEINFO_ENTRY="			Game	csgo/addons/metamod"
if [ -f "${GAMEINFO_FILE}" ]; then
    if grep -q "Game[[:blank:]]*csgo\/addons\/metamod" "$GAMEINFO_FILE"; then # match any whitespace
        log_message "File gameinfo.gi already configured. No changes were made." "success"
    else
        awk -v new_entry="$GAMEINFO_ENTRY" '
            BEGIN { found=0; }
            // {
                if (found) {
                    print new_entry;
                    found=0;
                }
                print;
            }
            /Game_LowViolence/ { found=1; }
        ' "$GAMEINFO_FILE" > "$GAMEINFO_FILE.tmp" && mv "$GAMEINFO_FILE.tmp" "$GAMEINFO_FILE"

        log_message "The file ${GAMEINFO_FILE} has been configured for MetaMod successfully." "success"
    fi
fi

# Cleanup and Update
cleanup_and_update() {
    # Directories
    GAME_DIRECTORY="./game/csgo"
    OUTPUT_DIR="./game/csgo/addons"
    TEMP_DIR="./temps"
    LOG_FILE="./game/startup_log.txt"  # Log file path
    VERSION_FILE="./game/versions.txt"  # Version file path

    # Delete previous log file if exists
    rm -f "$LOG_FILE"

    # File age intervals (in hours)
    BACKUP_ROUND_PURGE_INTERVAL=24
    DEMO_PURGE_INTERVAL=168
    CSS_JUNK_PURGE_INTERVAL=72
    ACCELERATOR_DUMPS_DIR="$OUTPUT_DIR/AcceleratorCS2/dumps"
    ACCELERATOR_DUMP_PURGE_INTERVAL=168

    mkdir -p "$TEMP_DIR"

    # Function to check if a file is older than a specified number of hours
    is_file_older_than() {
        local file="$1"
        local hours="$2"
        local current_time=$(date +%s)
        local file_time=$(date -r "$file" +%s)
        local age=$(( (current_time - file_time) / 3600 ))
        [ "$age" -gt "$hours" ]
    }

    # Function to safely delete a file
    safe_delete() {
        local file="$1"
        local category="$2"
        rm -f "$file"
        log_message "Deleted $category file: $file" "success"
    }

    # Function to purge files
    purge_files() {
        local directory="$1"
        local pattern="$2"
        local interval="$3"
        local category="$4"
        local count=0

        if [ -d "$directory" ]; then
            # Correct way to get files matching the pattern
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

    if [ "$CLEANUP_ENABLED" = "1" ]; then
        log_message "Starting cleanup..." "running"

        # Run all purge functions
        purge_files "$GAME_DIRECTORY" "*.txt" $BACKUP_ROUND_PURGE_INTERVAL "Logs"
        purge_files "$GAME_DIRECTORY" "*.dem" $DEMO_PURGE_INTERVAL "Demos"
        purge_files "$GAME_DIRECTORY/addons/counterstrikesharp/logs" "*.txt" $CSS_JUNK_PURGE_INTERVAL "CSS Logs"

        # Purge AcceleratorCS2 dump files if the directory exists
        if [ -d "$ACCELERATOR_DUMPS_DIR" ]; then
            purge_files "$ACCELERATOR_DUMPS_DIR" "*.dmp.txt" $ACCELERATOR_DUMP_PURGE_INTERVAL "Accelerator Logs"
            purge_files "$ACCELERATOR_DUMPS_DIR" "*.dmp" $ACCELERATOR_DUMP_PURGE_INTERVAL "Accelerator Dumps"
        fi

        log_message "Cleanup completed." "success"
    fi

    # Function to get the current version from the version file
    get_current_version() {
        local addon="$1"
        if [ -f "$VERSION_FILE" ];then
            grep "^$addon=" "$VERSION_FILE" | cut -d'=' -f2
        else
            echo ""
        fi
    }

    # Function to update the version file
    update_version_file() {
        local addon="$1"
        local new_version="$2"
        if grep -q "^$addon=" "$VERSION_FILE"; then
            sed -i "s/^$addon=.*/$addon=$new_version/" "$VERSION_FILE"
        else
            echo "$addon=$new_version" >> "$VERSION_FILE"
        fi
    }

    # Ensure versions.txt exists
    if [ ! -f "$VERSION_FILE" ]; then
        touch "$VERSION_FILE"
    fi

    # Update the update_addon function to correctly parse the asset URL
    update_addon() {
        local repo="$1"
        local output_path="$2"
        local temp_subdir="$3"
        local addon_name="$4"
        local current_version
        local new_version

        # Create the output directory and temporary subdirectory if they do not exist
        mkdir -p "$output_path"
        mkdir -p "$TEMP_DIR/$temp_subdir"

        # Purge the temporary subdirectory before downloading
        rm -rf "$TEMP_DIR/$temp_subdir"/*

        # GitHub repository details
        API_URL="https://api.github.com/repos/$repo/releases/latest"

        # Get the latest release information from GitHub API
        response=$(curl -s $API_URL)

        # Extract the download URL and tag name for the desired asset
        asset_url=$(echo $response | grep -oP '"browser_download_url": "\K[^"]+' | grep 'counterstrikesharp-with-runtime-build-.*-linux-.*\.zip')
        new_version=$(echo $response | grep -oP '"tag_name": "\K[^"]+')

        # Get the current version from the version file
        current_version=$(get_current_version "$addon_name")

        # Check if a newer version is available
        if [ "$current_version" != "$new_version" ]; then
            log_message "New version of $addon_name available: $new_version (current: $current_version)" "running"

            # Check if the asset URL was found
            if [ -z "$asset_url" ]; then
                log_message "Failed to find the asset URL for $repo. Skipping update." "error"
                return 1
            fi

            # Extract the file name from the asset URL
            file_name=$(basename $asset_url)

            # Download the asset
            log_message "Downloading $file_name..." "running"
            curl -fsSL -m 300 -o "$TEMP_DIR/$temp_subdir/$file_name" "$asset_url"
            if [ $? -ne 0 ]; then
                log_message "Failed to download $file_name from $asset_url" "error"
                return 1
            fi

            # Verify that the file has been downloaded correctly
            if [ ! -s "$TEMP_DIR/$temp_subdir/$file_name" ]; then
                log_message "Downloaded file $file_name is empty or not found." "error"
                return 1
            fi

            # Extract the downloaded file to the temporary subdirectory using unzip
            log_message "Extracting $file_name..." "running"
            unzip -qq -o "$TEMP_DIR/$temp_subdir/$file_name" -d "$TEMP_DIR/$temp_subdir"

            # Check if the extraction was successful
            if [ $? -ne 0 ]; then
                log_message "Failed to extract $file_name. Skipping update." "error"
                return 1
            fi

            # Copy the contents of the extracted 'addons' directory to the output directory, overriding existing files
            log_message "Copying files to $output_path..." "running"
            cp -r "$TEMP_DIR/$temp_subdir/addons/." "$output_path"

            # Update the version file
            update_version_file "$addon_name" "$new_version"

            log_message "Update of $repo completed successfully." "success"
        else
            log_message "No new version of $addon_name available. Skipping update." "success"
        fi
    }

    if [ "$METAMOD_AUTOUPDATE" = "1" ] || ([ ! -d "$OUTPUT_DIR/metamod" ] && [ "$CSS_AUTOUPDATE" = "1" ]); then
        if [ ! -d "$OUTPUT_DIR/metamod" ]; then
            log_message "Metamod not installed. Installing Metamod..." "running"
        else
            log_message "Updating Metamod..." "running"
        fi

        metamod_version=$(curl -sL https://mms.alliedmods.net/mmsdrop/2.0/ | grep -oP 'href="\K(mmsource-[^"]*-linux\.tar\.gz)' | tail -1)

        # Check if the version was successfully fetched
        if [ -z "$metamod_version" ]; then
            log_message "Failed to fetch the Metamod version." "error"
            exit 1
        fi

        # Construct the full URL to the Metamod tar.gz file
        full_url="https://mms.alliedmods.net/mmsdrop/2.0/$metamod_version"
        new_version=$(echo $metamod_version | grep -oP 'git\d+')

        # Get the current version from the version file
        current_version=$(get_current_version "Metamod")

        # Check if a newer version is available
        if [ "$current_version" != "$new_version" ]; then
            log_message "New version of Metamod available: $new_version (current: $current_version)" "running"

            # Log the URL being accessed
            log_message "Downloading Metamod from URL: $full_url" "running"

            # Download the latest Metamod release for Linux
            http_code=$(curl -s -L -w "%{http_code}" -o "$TEMP_DIR/metamod.tar.gz" "$full_url")
            if [ "$http_code" -ne 200 ]; then
                log_message "Failed to download Metamod from $full_url. HTTP status code: $http_code" "error"
                return 1
            fi

            # Verify that the file has been downloaded correctly
            if [ ! -s "$TEMP_DIR/metamod.tar.gz" ]; then
                log_message "Downloaded Metamod file is empty or not found." "error"
                return 1
            fi

            # Create the extraction directory
            mkdir -p "$TEMP_DIR/metamod"

            # Extract the downloaded Metamod archive to the temporary directory
            log_message "Extracting Metamod archive..." "running"
            tar -xzf "$TEMP_DIR/metamod.tar.gz" -C "$TEMP_DIR/metamod" || {
                log_message "Failed to extract Metamod archive. Skipping update." "error"
                return 1
            }

            # Copy the contents of the extracted 'addons' directory to the output directory, overriding existing files
            log_message "Copying files to $OUTPUT_DIR..." "running"
            cp -rf "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/"

            # Update the version file
            update_version_file "Metamod" "$new_version"

            log_message "Metamod update completed successfully." "success"
        else
            log_message "No new version of Metamod available. Skipping update." "success"
        fi
    fi

    if [ "$CSS_AUTOUPDATE" = "1" ]; then
        log_message "Updating CounterStrikeSharp..." "running"
        update_addon "roflmuffin/CounterStrikeSharp" "$OUTPUT_DIR" "css" "CSS"
    fi

    # Clean up
    log_message "Cleaning up temporary files..." "running"
    rm -rf "$TEMP_DIR"
    log_message "Cleanup completed." "success"
}

# Run cleanup and update
cleanup_and_update || log_message "Cleanup and update encountered errors but proceeding to start the server." "error"

# Create and read the mute_messages.cfg file only if the filter is enabled
if [ "$ENABLE_FILTER" = "1" ]; then
    # Create the mute_messages.cfg file with example patterns if it doesn't exist
    if [ ! -f "./game/mute_messages.cfg" ]; then
        cat <<EOL > ./game/mute_messages.cfg
# Mute Messages Configuration File
# Add patterns of messages to be blocked.
# One line is one check. If the line is like "asd", then the message should be blocked if it equals "asd".
# If the line is like ".*asd.*", then block the message if the line contains "asd" with anything before or after.
# Example pattern to block messages containing "Certificate expires":
# .*Certificate expires.*

.*Certificate expires.*
EOL
        log_message "Created ./game/mute_messages.cfg with example patterns. You can modify this file to specify additional messages to mute." "running"
    else
        log_message "./game/mute_messages.cfg already exists. You can modify this file to specify additional messages to mute." "success"
    fi

    # No default basic patterns for now
    BASIC_PATTERNS=()

    # Load user-defined mute patterns from configuration file
    USER_PATTERNS=()
    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
        # Ignore comment lines and empty lines
        [[ $pattern =~ ^#.*$ ]] && continue
        [[ -z "$pattern" ]] && continue
        USER_PATTERNS+=("$pattern")
    done < ./game/mute_messages.cfg

    # Log the number of user patterns loaded
    log_message "Loaded ${#USER_PATTERNS[@]} user-defined patterns from ./game/mute_messages.cfg" "running"

    # Combine basic patterns and user-defined patterns if they are not empty
    MUTE_PATTERNS=()
    if [ ${#BASIC_PATTERNS[@]} -gt 0 ]; then
        MUTE_PATTERNS=("${BASIC_PATTERNS[@]}")
    fi
    if [ ${#USER_PATTERNS[@]} -gt 0 ]; then
        MUTE_PATTERNS+=("${USER_PATTERNS[@]}")
    fi

    # Remove any empty patterns
    MUTE_PATTERNS=("${MUTE_PATTERNS[@]}")
else
    log_message "Filter is disabled. No messages will be blocked." "running"
fi

# Replace Startup Variables
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))
MODIFIED_STARTUP="unbuffer -p ${MODIFIED_STARTUP}"

log_message "Starting server with command: ${MODIFIED_STARTUP}" "running"

# Function to handle server output
handle_server_output() {
  local line="$1"
  local server_stopped=false

  # Check if the line indicates server shutdown
  if [[ "$line" == *"Server shutting down"* ]]; then
    server_stopped=true
  fi

  # Process the line (existing logic)
  if [ "$ENABLE_FILTER" = "1" ]; then
    BLOCKED=false
    for pattern in "${MUTE_PATTERNS[@]}"; do
      if [[ $line =~ $pattern ]]; then
        if [ "$FILTER_PREVIEW_MODE" = "1" ]; then
          log_message "Message Block Preview: $line" "error"
        fi
        BLOCKED=true
        break
      fi
    done
    if [ "$BLOCKED" = false ] && [ -n "$line" ]; then
      printf '%s\n' "$line"
    fi
  else
    if [ -n "$line" ]; then
      printf '%s\n' "$line"
    fi
  fi

  # If server has stopped, log the success message
  if [ "$server_stopped" = true ]; then
    log_message "The server is shutting down..." "success"
  fi
}

# Run the Server
$MODIFIED_STARTUP 2>&1 | while IFS= read -r line; do
  # Trim trailing whitespace and newlines
  line=$(echo -n "$line" | sed -e 's/[[:space:]]*$//')

  # Skip Segmentation fault messages related to server shutdown
  if [[ "$line" == *"Segmentation fault"* && "$line" == *"${GAMEEXE}"* ]]; then
    continue
  fi

  handle_server_output "$line"
done

log_message "Server has stopped successfully." "success"
