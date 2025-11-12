#!/bin/bash
source /utils/logging.sh
source /utils/version.sh
source /utils/updater_common.sh

# Directories
GAME_DIRECTORY="./game/csgo"
OUTPUT_DIR="./game/csgo/addons"
TEMP_DIR="./temps"
ACCELERATOR_DUMPS_DIR="$OUTPUT_DIR/AcceleratorCS2/dumps"

# Source modular updaters
source /scripts/updaters/metamod.sh
source /scripts/updaters/counterstrikesharp.sh
source /scripts/updaters/swiftlys2.sh
source /scripts/updaters/modsharp.sh

# Main addon update function based on ADDON_SELECTION
update_addons() {
    # Cleanup if enabled
    if [ "${CLEANUP_ENABLED:-0}" -eq 1 ]; then
        cleanup
    fi

    mkdir -p "$TEMP_DIR"

    # Metamod (required for CSS)
    if [ "${ADDON_SELECTION}" = "Metamod Only" ] || [ "${ADDON_SELECTION}" = "Metamod + CounterStrikeSharp" ]; then
        if type update_metamod &>/dev/null; then
            update_metamod
        else
            log_message "update_metamod function not available" "error"
        fi

        # Configure metamod in gameinfo.gi
        if type configure_metamod &>/dev/null; then
            configure_metamod
        fi
    fi

    # CounterStrikeSharp
    if [ "${ADDON_SELECTION}" = "Metamod + CounterStrikeSharp" ]; then
        if type update_counterstrikesharp &>/dev/null; then
            update_counterstrikesharp
        else
            log_message "update_counterstrikesharp function not available" "error"
        fi
    fi

    # SwiftlyS2 (standalone)
    if [ "${ADDON_SELECTION}" = "SwiftlyS2" ]; then
        if type update_swiftly &>/dev/null; then
            update_swiftly
        else
            log_message "update_swiftly function not available" "error"
        fi

        # Configure swiftlys2 in gameinfo.gi
        if type configure_swiftly &>/dev/null; then
            configure_swiftly
        fi
    fi

    # ModSharp (standalone)
    if [ "${ADDON_SELECTION}" = "ModSharp" ]; then
        if [ -f "/scripts/updaters/modsharp.sh" ]; then
            bash /scripts/updaters/modsharp.sh
        else
            log_message "ModSharp updater script not found" "error"
        fi

        # Configure modsharp in gameinfo.gi
        if type configure_modsharp &>/dev/null; then
            configure_modsharp
        fi
    fi

    # Clean up
    rm -rf "$TEMP_DIR"
}

