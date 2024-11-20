#!/bin/bash

# This file makes sure that all required environment variables are set.
# So if the user of the egg removes a variable from the panel, the default values will be used from here.

# Auto-update configuration
export UPDATE_AUTO_RESTART=${UPDATE_AUTO_RESTART:-0}      # Enable auto-restart on update
export UPDATE_COUNTDOWN_TIME=${UPDATE_COUNTDOWN_TIME:-300} # Countdown time before restart (seconds)
export VERSION_CHECK_INTERVAL=${VERSION_CHECK_INTERVAL:-60}

# Plugin auto-update configuration
export METAMOD_AUTOUPDATE=${METAMOD_AUTOUPDATE:-0}       # Enable MetaMod auto-update
export CSS_AUTOUPDATE=${CSS_AUTOUPDATE:-0}               # Enable CounterStrikeSharp auto-update

# Maintenance configuration
export CLEANUP_ENABLED=${CLEANUP_ENABLED:-0}              # Enable cleanup of old files
export ENABLE_FILTER=${ENABLE_FILTER:-0}                  # Enable message filtering
export FILTER_PREVIEW_MODE=${FILTER_PREVIEW_MODE:-0}      # Preview filtered messages

# Logging configuration
export LOG_LEVEL=${LOG_LEVEL:-"INFO"}                     # Log level
export LOG_FILE_ENABLED=${LOG_FILE_ENABLED:-0}            # Enable logging to file