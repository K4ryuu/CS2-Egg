#!/bin/bash
source /utils/logging.sh

# Format bytes to human readable string
format_bytes() {
    local size="$1"
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return 1
    fi
    if [ "$size" -ge 1099511627776 ]; then # TB
        awk -v s="$size" 'BEGIN { printf "%.2f TB", s/1099511627776 }'
    elif [ "$size" -ge 1073741824 ]; then # GB
        awk -v s="$size" 'BEGIN { printf "%.2f GB", s/1073741824 }'
    elif [ "$size" -ge 1048576 ]; then # MB
        awk -v s="$size" 'BEGIN { printf "%.2f MB", s/1048576 }'
    elif [ "$size" -ge 1024 ]; then # KB
        awk -v s="$size" 'BEGIN { printf "%.2f KB", s/1024 }'
    else
        echo "${size} B"
    fi
}

# VPK Sync Feature - saves TONS of space by symlinking game files
# Instead of each server having 30GB of game files, they share one centralized copy
# Benefits:
# - Each server only needs ~3GB (just configs and workshop stuff)
# - Update once, all servers get it instantly
# - Way less bandwidth and disk usage
# - Configs stay separate per-server

sync_files() {
    # Bail early if sync isn't configured
    if [ -z "${SYNC_LOCATION}" ] || [ "${SYNC_LOCATION}" == "" ]; then
        return 0
    fi

    local src_dir="${SYNC_LOCATION}"
    local dest_dir="/home/container"

    # Make sure the source directory actually exists
    if [ ! -d "$src_dir" ]; then
        log_message "Sync location not found: $src_dir" "warning"
        return 0
    fi

    log_message "Syncing VPK files..." "info"

    # Sync everything EXCEPT .vpk files, configs, and gameinfo.gi
    # We'll symlink VPKs separately to save space
    # gameinfo.gi is excluded to preserve addon configurations
    if rsync -aKLz --exclude '*.vpk' --exclude 'cfg/' --exclude 'game/csgo/gameinfo.gi' "$src_dir/" "$dest_dir" 2>/dev/null; then
        : # base files synced silently
    else
        log_message "Failed to sync base files" "error"
        return 1
    fi

    # Copy gameinfo.gi only if it doesn't exist (first boot)
    local gameinfo_src="$src_dir/game/csgo/gameinfo.gi"
    local gameinfo_dest="$dest_dir/game/csgo/gameinfo.gi"
    if [ -f "$gameinfo_src" ] && [ ! -f "$gameinfo_dest" ]; then
        cp "$gameinfo_src" "$gameinfo_dest" 2>/dev/null
        log_message "Copied initial gameinfo.gi" "debug"
    fi

    # Now create symlinks for all the VPK files
    # This is where we save the big bucks (~56GB of VPKs)
    local vpk_count=0
    local vpk_total_size=0
    while IFS= read -r -d '' vpk_file; do
        rel_path="${vpk_file#$src_dir/}"
        link_path="$dest_dir/$rel_path"

        # Make sure the directory exists before linking
        mkdir -p "$(dirname "$link_path")" 2>/dev/null

        # Determine file size
        file_size=$(stat -c %s "$vpk_file" 2>/dev/null || stat -f %z "$vpk_file" 2>/dev/null || echo 0)
        [[ "$file_size" =~ ^[0-9]+$ ]] || file_size=0

        # Remove existing file/link if present
        if [ -e "$link_path" ] || [ -L "$link_path" ]; then
            rm -f "$link_path" 2>/dev/null
        fi

        # Create the symlink
        if ln -sf "$vpk_file" "$link_path" 2>/dev/null; then
            ((vpk_count++))
            vpk_total_size=$((vpk_total_size + file_size))
        else
            log_message "Failed to link: $rel_path" "warning"
        fi
    done < <(find "$src_dir" -type f -name "*.vpk" -print0 2>/dev/null)

    local human_total
    human_total=$(format_bytes "$vpk_total_size")
    log_message "VPK sync complete — linked ${vpk_count} file(s), total VPK size ${human_total} (approx. per-server saving)" "success"

    return 0
}

sync_cfg_files() {
    # Skip if sync isn't set up
    if [ -z "${SYNC_LOCATION}" ] || [ "${SYNC_LOCATION}" == "" ]; then
        return 0
    fi

    local src_dir="${SYNC_LOCATION}"
    local dest_dir="/home/container"
    local cfg_src_dir="$src_dir/game/csgo/cfg"
    local cfg_dest_dir="$dest_dir/game/csgo/cfg"

    # Bail if there's no cfg directory to sync
    if [ ! -d "$cfg_src_dir" ]; then
        return 0
    fi

    # Make sure the destination cfg dir exists
    mkdir -p "$cfg_dest_dir" 2>/dev/null

    # Copy default config files ONLY if they don't already exist
    # This way we don't overwrite user's custom configs
    local synced_count=0
    find "$cfg_src_dir" -type f \( -name "*.cfg" -o -name "*.vcfg" \) -print0 2>/dev/null | while IFS= read -r -d '' cfg_file; do
        local filename="$(basename "$cfg_file")"
        local dest_file="$cfg_dest_dir/$filename"

        if [ ! -e "$dest_file" ]; then
            if cp "$cfg_file" "$dest_file" 2>/dev/null; then
                ((synced_count++))
            else
                log_message "Failed to copy: $filename" "warning"
            fi
        fi
    done

    if [ $synced_count -gt 0 ]; then
        log_message "Synced $synced_count default config file(s)" "debug"
    fi

    return 0
}

# Export these so entrypoint can use them
export -f sync_files
export -f sync_cfg_files
