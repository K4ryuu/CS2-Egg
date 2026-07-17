#!/bin/bash
source /utils/logging.sh
source /utils/updater_common.sh

# Directories
GAME_DIRECTORY="./game/csgo"
OUTPUT_DIR="./game/csgo/addons"
TEMP_DIR="./temps"

# Source modular updaters
source /scripts/updaters/metamod.sh
source /scripts/updaters/counterstrikesharp.sh
source /scripts/updaters/swiftlys2.sh
source /scripts/updaters/modsharp.sh
source /scripts/updaters/matchzy.sh
source /scripts/updaters/weaponpaints.sh

# Backwards compatibility: Map old ADDON_SELECTION to new boolean variables
migrate_addon_selection() {
    if [ -n "${ADDON_SELECTION}" ]; then
        case "${ADDON_SELECTION}" in
            "Metamod Only")
                INSTALL_METAMOD=1
                ;;
            "Metamod + CounterStrikeSharp")
                INSTALL_METAMOD=1
                INSTALL_CSS=1
                ;;
            "SwiftlyS2")
                INSTALL_SWIFTLY=1
                ;;
            "ModSharp")
                INSTALL_MODSHARP=1
                ;;
        esac
    fi
}

# Main addon update function based on boolean variables
update_addons() {
    # Cleanup if enabled
    if [ "${CLEANUP_ENABLED:-0}" -eq 1 ]; then
        cleanup
    fi

    mkdir -p "$TEMP_DIR"

    # Backwards compatibility migration
    migrate_addon_selection

# MatchZy and WeaponPaints are CounterStrikeSharp plugins.
    if [ "${INSTALL_MATCHZY:-0}" -eq 1 ] ||
       [ "${INSTALL_WEAPONPAINTS:-0}" -eq 1 ]; then

    if [ "${INSTALL_CSS:-0}" -ne 1 ]; then
        log_message \
            "MatchZy/WeaponPaints requires CounterStrikeSharp; auto-enabling it..." \
            "warning"
    fi

    INSTALL_CSS=1
    fi


    # Dependency check: CSS requires MetaMod
    if [ "${INSTALL_CSS:-0}" -eq 1 ] && [ "${INSTALL_METAMOD:-0}" -ne 1 ]; then
        log_message "CounterStrikeSharp requires MetaMod:Source, auto-enabling..." "warning"
        INSTALL_METAMOD=1
    fi

    # Consolidated ModSharp incompatibility check
    modsharp_is_present=false
    if [ "${INSTALL_MODSHARP:-0}" -eq 1 ] || grep -q "Game[[:space:]]*sharp" "/home/container/game/csgo/gameinfo.gi" 2>/dev/null; then
        modsharp_is_present=true
    fi

    if [ "$modsharp_is_present" = true ]; then
        if [ "${INSTALL_CSS:-0}" -eq 1 ]; then
            log_message "ModSharp is present alongside CounterStrikeSharp. These addons may be incompatible and may cause conflicts. It is recommended to use only one of them." "warning"
        fi

        if [ "${INSTALL_SWIFTLY:-0}" -eq 1 ]; then
            log_message "ModSharp is present alongside SwiftlyS2. These addons may be incompatible and may cause conflicts. It is recommended to use only one of them." "warning"
        fi
    fi

    # MetaMod:Source
    if [ "${INSTALL_METAMOD:-0}" -eq 1 ]; then
        update_metamod

        # Configure metamod in gameinfo.gi
        add_to_gameinfo "csgo/addons/metamod"
    fi

    # CounterStrikeSharp
    if [ "${INSTALL_CSS:-0}" -eq 1 ]; then
        update_counterstrikesharp
    fi

    # MatchZy
    if [ "${INSTALL_MATCHZY:-0}" -eq 1 ]; then
        if type update_matchzy &>/dev/null; then
        update_matchzy
        else
        log_message \
            "update_matchzy function not available" \
            "error"
        fi
    fi

    # WeaponPaints and its dependencies
    if [ "${INSTALL_WEAPONPAINTS:-0}" -eq 1 ]; then
        if type update_weaponpaints &>/dev/null; then
        update_weaponpaints
        else
        log_message \
            "update_weaponpaints function not available" \
            "error"
        fi
    fi

    # SwiftlyS2 (standalone)
    if [ "${INSTALL_SWIFTLY:-0}" -eq 1 ]; then
        update_swiftly

        # Configure swiftlys2 in gameinfo.gi
        add_to_gameinfo "csgo/addons/swiftlys2"

        # Remove old metamod VDF file if present
        local OLD_VDF="/home/container/game/csgo/addons/metamod/swiftlys2.vdf"
        if [ -f "$OLD_VDF" ]; then
            rm -f "$OLD_VDF"
            log_message "Removed old swiftlys2.vdf from metamod" "debug"
        fi
    fi

    # ModSharp (standalone)
    if [ "${INSTALL_MODSHARP:-0}" -eq 1 ]; then
        update_modsharp

        # Configure modsharp in gameinfo.gi
        add_to_gameinfo "sharp"
    fi

    # Ensure MetaMod is always first addon after LowViolence (if present)
    ensure_metamod_first

    # Patch RequireLoginForDedicatedServers setting based on ALLOW_TOKENLESS
    patch_tokenless_setting

    # Clean up
    rm -rf "$TEMP_DIR"
}

