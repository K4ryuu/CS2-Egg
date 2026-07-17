#!/bin/bash

source /utils/logging.sh
source /utils/updater_common.sh

CSS_ROOT="/home/container/game/csgo/addons/counterstrikesharp"
PLUGIN_ROOT="$CSS_ROOT/plugins"

install_css_plugin_release() {
    local display_name="$1"
    local repo="$2"
    local asset_pattern="$3"
    local version_key="$4"
    local plugin_dir="$5"
    local dll_name="$6"

    local slug
    slug=$(echo "$version_key" | tr '[:upper:]' '[:lower:]')

    local temp_dir="$TEMP_DIR/$slug"
    local archive="$TEMP_DIR/$slug.zip"
    local target_dir="$PLUGIN_ROOT/$plugin_dir"

    local release_info
    local new_version
    local asset_url
    local current_version

    rm -rf "$temp_dir" "$archive"
    mkdir -p "$temp_dir" "$PLUGIN_ROOT"

    # Keep third-party plugins on stable releases even if the egg's
    # framework PRERELEASE option is enabled.
    release_info=$(
        PRERELEASE=0 get_github_release \
            "$repo" \
            "$asset_pattern"
    )

    if [ -z "$release_info" ] ||
       ! echo "$release_info" | jq -e . >/dev/null 2>&1; then
        log_message \
            "Failed to get release information for $display_name" \
            "error"
        return 1
    fi

    new_version=$(echo "$release_info" | jq -r '.version // empty')
    asset_url=$(echo "$release_info" | jq -r '.asset_url // empty')
    current_version=$(get_current_version "$version_key")

    # Force reinstall when the version record exists but plugin files
    # are missing.
    if [ ! -f "$target_dir/$dll_name" ]; then
        current_version=""
    fi

    if [ -z "$new_version" ] || [ -z "$asset_url" ]; then
        log_message \
            "No suitable release asset was found for $display_name" \
            "error"
        return 1
    fi

    if ! check_version \
        "$display_name" \
        "${current_version:-none}" \
        "$new_version"; then
        return 0
    fi

    if ! handle_download_and_extract \
        "$asset_url" \
        "$archive" \
        "$temp_dir" \
        "zip"; then
        return 1
    fi

    # Locate the plugin DLL instead of assuming a fixed ZIP layout.
    local dll_path
    local source_dir

    dll_path=$(
        find "$temp_dir" \
            -type f \
            -name "$dll_name" |
        head -n1
    )

    if [ -z "$dll_path" ]; then
        log_message \
            "$dll_name was not found in the $display_name archive" \
            "error"
        return 1
    fi

    source_dir=$(dirname "$dll_path")

    # Plugin-generated configs are outside the plugin directory, so
    # replacing the release folder will not delete database settings.
    rm -rf "$target_dir"
    mkdir -p "$target_dir"

    rsync -a \
        "$source_dir/" \
        "$target_dir/"

    update_version_file \
        "$version_key" \
        "$new_version"

    log_message \
        "$display_name updated to $new_version" \
        "success"
}

configure_weaponpaints() {
    local wp_dir="$PLUGIN_ROOT/WeaponPaints"
    local gamedata_source

    gamedata_source=$(
        find "$wp_dir" \
            -type f \
            -iname 'weaponpaints.json' |
        head -n1
    )

    # WeaponPaints requires this file in the global CSS gamedata directory.
    if [ -n "$gamedata_source" ]; then
        mkdir -p "$CSS_ROOT/gamedata"

        install -m 0644 \
            "$gamedata_source" \
            "$CSS_ROOT/gamedata/weaponpaints.json"

        log_message \
            "WeaponPaints gamedata installed" \
            "success"
    else
        log_message \
            "weaponpaints.json was not found in the WeaponPaints plugin folder" \
            "warning"
    fi

    local core_json="$CSS_ROOT/configs/core.json"

    if [ "${WEAPONPAINTS_ACCEPT_GSLT_RISK:-0}" -eq 1 ]; then
        if [ -f "$core_json" ]; then
            local tmp_json="${core_json}.tmp"

            if jq \
                '.FollowCS2ServerGuidelines = false' \
                "$core_json" > "$tmp_json"; then

                mv "$tmp_json" "$core_json"

                log_message \
                    "Set FollowCS2ServerGuidelines=false for WeaponPaints" \
                    "warning"
            else
                rm -f "$tmp_json"

                log_message \
                    "Failed to update CounterStrikeSharp core.json" \
                    "error"

                return 1
            fi
        else
            log_message \
                "CounterStrikeSharp core.json does not exist yet; restart once after its first creation" \
                "warning"
        fi
    else
        log_message \
            "WeaponPaints installed, but the CounterStrikeSharp guideline bypass was not enabled. Set WEAPONPAINTS_ACCEPT_GSLT_RISK=1 only after accepting the GSLT-ban risk." \
            "warning"
    fi
}

update_weaponpaints() {
    # Dependency 1: database library
    install_css_plugin_release \
        "AnyBaseLib" \
        "NickFox007/AnyBaseLibCS2" \
        '^AnyBaseLib\.zip$' \
        "ANYBASELIB" \
        "AnyBaseLib" \
        "AnyBaseLib.dll" || return 1

    # Dependency 2: player settings storage
    install_css_plugin_release \
        "PlayerSettings" \
        "NickFox007/PlayerSettingsCS2" \
        '^PlayerSettings\.zip$' \
        "PLAYERSETTINGS" \
        "PlayerSettings" \
        "PlayerSettings.dll" || return 1

    # Dependency 3: menu system
    install_css_plugin_release \
        "MenuManagerCore" \
        "NickFox007/MenuManagerCS2" \
        '^MenuManager\.zip$' \
        "MENUMANAGER" \
        "MenuManagerCore" \
        "MenuManagerCore.dll" || return 1

    # WeaponPaints plugin only; exclude WeaponPaints-Website.zip.
    install_css_plugin_release \
        "WeaponPaints" \
        "Nereziel/cs2-WeaponPaints" \
        '^WeaponPaints\.zip$' \
        "WEAPONPAINTS" \
        "WeaponPaints" \
        "WeaponPaints.dll" || return 1

    configure_weaponpaints
}

main() {
    mkdir -p "$TEMP_DIR"
    update_weaponpaints
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
