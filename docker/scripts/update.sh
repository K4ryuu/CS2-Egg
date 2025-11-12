#!/bin/bash
source /utils/logging.sh
source /utils/version.sh
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

    # Dependency check: CSS requires MetaMod
    if [ "${INSTALL_CSS:-0}" -eq 1 ] && [ "${INSTALL_METAMOD:-0}" -ne 1 ]; then
        log_message "CounterStrikeSharp requires MetaMod:Source, auto-enabling..." "warning"
        INSTALL_METAMOD=1
    fi

    # Compatibility check: ModSharp is incompatible with CSS and SwiftlyS2
    # If CSS or SwiftlyS2 is enabled, disable ModSharp (they have priority)
    if [ "${INSTALL_MODSHARP:-0}" -eq 1 ]; then
        if [ "${INSTALL_CSS:-0}" -eq 1 ] || [ "${INSTALL_SWIFTLY:-0}" -eq 1 ]; then
            log_message "ModSharp is incompatible with CSS/SwiftlyS2, disabling ModSharp..." "warning"
            INSTALL_MODSHARP=0
            remove_from_gameinfo "sharp"
        fi
    fi

    # MetaMod:Source
    if [ "${INSTALL_METAMOD:-0}" -eq 1 ]; then
        if type update_metamod &>/dev/null; then
            update_metamod
        else
            log_message "update_metamod function not available" "error"
        fi

        # Configure metamod in gameinfo.gi
        add_to_gameinfo "csgo/addons/metamod"
    fi

    # CounterStrikeSharp
    if [ "${INSTALL_CSS:-0}" -eq 1 ]; then
        if type update_counterstrikesharp &>/dev/null; then
            update_counterstrikesharp
        else
            log_message "update_counterstrikesharp function not available" "error"
        fi
    fi

    # SwiftlyS2 (standalone)
    if [ "${INSTALL_SWIFTLY:-0}" -eq 1 ]; then
        if type update_swiftly &>/dev/null; then
            update_swiftly
        else
            log_message "update_swiftly function not available" "error"
        fi

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
        if [ -f "/scripts/updaters/modsharp.sh" ]; then
            bash /scripts/updaters/modsharp.sh
        else
            log_message "ModSharp updater script not found" "error"
        fi

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

