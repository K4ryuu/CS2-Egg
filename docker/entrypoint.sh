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
  local type="$2"  # Type: running, error, success

  case $type in
    running)
      echo -e "${PREFIX}${YELLOW}${message}${NC}"
      ;;
    error)
      echo -e "${PREFIX}${RED}${message}${NC}"
      ;;
    success)
      echo -e "${PREFIX}${GREEN}${message}${NC}"
      ;;
    *)
      echo -e "${PREFIX}${WHITE}${message}${NC}"
      ;;
  esac
}

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
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} +quit"
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
                        STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
                    else
                        STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/container +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
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

    # Colors for log messages using tput
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    WHITE='\033[0;37m'
    NC='\033[0m' # No Color

    # Prefix for logs
    PREFIX="${RED}[KitsuneLab]${WHITE} > "

    # Delete previous log file if exists
    rm -f "$LOG_FILE"

    # File age intervals (in hours)
    BACKUP_ROUND_PURGE_INTERVAL=24
    DEMO_PURGE_INTERVAL=168
    CSS_JUNK_PURGE_INTERVAL=72
    ACCELERATOR_DUMPS_DIR="$OUTPUT_DIR/AcceleratorCS2/dumps"
    ACCELERATOR_DUMP_PURGE_INTERVAL=168

    # Variables to control whether to run the cleanup and update
    CLEANUP_ENABLED=1
    RUN_CSS_UPDATE=1
    RUN_METAMOD_UPDATE=1

    mkdir -p "$TEMP_DIR"

    log_message() {
        local message="$1"
        local type="$2"  # Type: running, error, success

        case $type in
            running)
                echo -e "${PREFIX}${YELLOW}${message}${NC}" | tee -a "$LOG_FILE"
                ;;
            error)
                echo -e "${PREFIX}${RED}${message}${NC}" | tee -a "$LOG_FILE"
                ;;
            success)
                echo -e "${PREFIX}${GREEN}${message}${NC}" | tee -a "$LOG_FILE"
                ;;
            *)
                echo -e "${PREFIX}${WHITE}${message}${NC}" | tee -a "$LOG_FILE"
                ;;
        esac
    }

    # Error handling function
    handle_error() {
      local exit_code="$?"
      local command="$1"
      log_message "Error occurred while executing: $command" "error"
      log_message "Exit code: $exit_code" "error"
      exit "$exit_code"
    }

    # Set error handling trap
    trap 'handle_error "$BASH_COMMAND"' ERR

    if [ "$CLEANUP_ENABLED" = "1" ]; then
      log_message "Starting cleanup..." "running"

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
          rm "$file"
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
              local files=("$directory"/"$pattern")
              for file in "${files[@]}"; do
                  if [ -f "$file" ] && is_file_older_than "$file" "$interval"; then
                      safe_delete "$file" "$category"
                      ((count++))
                  fi
              done
          fi
          log_message "Deleted $count files in category: $category" "success"
      }

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
      if [ -f "$VERSION_FILE" ]; then
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

            # Log the URL being accessed
            log_message "Downloading from URL: $asset_url" "running"

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

    if [ "$RUN_METAMOD_UPDATE" = "1" ] || ([ ! -d "$OUTPUT_DIR/metamod" ] && [ "$RUN_CSS_UPDATE" = "1" ]); then
    if [ ! -d "$OUTPUT_DIR/metamod" ]; then
        log_message "Metamod not installed. Installing Metamod..." "running"
    else
        log_message "Updating Metamod..." "running"
    fi

    # Get the latest Metamod release URL
    metamod_url=$(curl -s https://mms.alliedmods.net/mmsdrop/2.0/ | grep -oP 'mmsource-2\.0\.\d+-git\d+-linux\.tar\.gz' | sort -r | head -n 1)
    full_url="https://mms.alliedmods.net/mmsdrop/2.0/$metamod_url"
    new_version=$(echo $metamod_url | grep -oP 'git\K\d+')

    # Get the current version from the version file
    current_version=$(get_current_version "Metamod")

    # Check if a newer version is available
    if [ "$current_version" != "$new_version" ]; then
        log_message "New version of Metamod available: $new_version (current: $current_version)" "running"

        # Log the URL being accessed
        log_message "Downloading Metamod from URL: $full_url" "running"

        # Download the latest Metamod release for Linux
        curl -s -L -w "%{http_code}" -o "$TEMP_DIR/metamod.tar.gz" "$full_url" | {
        read http_code
        if [ "$http_code" -ne 200 ]; then
            log_message "Failed to download Metamod from $full_url. HTTP status code: $http_code" "error"
            exit 1
        fi
        }

        # Verify that the file has been downloaded correctly
        if [ ! -s "$TEMP_DIR/metamod.tar.gz" ]; then
        log_message "Downloaded Metamod file is empty or not found." "error"
        exit 1
        fi

        # Create the extraction directory
        mkdir -p "$TEMP_DIR/metamod"

        # Extract the downloaded Metamod archive to the temporary directory
        log_message "Extracting Metamod archive..." "running"
        tar -xzf "$TEMP_DIR/metamod.tar.gz" -C "$TEMP_DIR/metamod"

        # Check if the extraction was successful
        if [ $? -ne 0 ]; then
        log_message "Failed to extract Metamod archive. Skipping update." "error"
        exit 1
        fi

        # Copy the contents of the extracted 'addons' directory to the output directory, overriding existing files
        log_message "Copying files to $OUTPUT_DIR..." "running"
        cp -ru "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/"

        # Update the version file
        update_version_file "Metamod" "$new_version"

        log_message "Metamod update completed successfully." "success"
    else
        log_message "No new version of Metamod available. Skipping update." "success"
    fi
    fi

    if [ "$RUN_CSS_UPDATE" = "1" ]; then
        log_message "Updating CounterStrikeSharp..." "running"
        update_addon "roflmuffin/CounterStrikeSharp" "$OUTPUT_DIR" "css" "CSS"
    fi

    # Clean up
    log_message "Cleaning up temporary files..." "running"
    rm -rf "$TEMP_DIR"
    log_message "Cleanup completed." "success"
}

# Run cleanup and update
cleanup_and_update

# Replace Startup Variables
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`
log_message ":/home/container$ ${MODIFIED_STARTUP}" "running"

# Run the Server
eval ${MODIFIED_STARTUP}