#!/bin/bash
set -e

# --- Configuration Loading ---
# Find the config file in the same directory as this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE="${SCRIPT_DIR}/factorio_updater.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at ${CONFIG_FILE}" >&2
    exit 1
fi
source "$CONFIG_FILE"
# --- Start Factorio Server ---
# --- Dynamic Path Generation ---
FACTORIO_INSTALL_DIR="${FACTORIO_BASE_DIR}/factorio"
FACTORIO_BIN="${FACTORIO_INSTALL_DIR}/bin/x64/factorio"
SAVE_FILE_PATH="${FACTORIO_INSTALL_DIR}/saves/${SAVE_FILE_NAME}"
SERVER_SETTINGS_PATH="${FACTORIO_INSTALL_DIR}/config/server-settings.json"

# --- Pre-flight Checks ---
# Ensure critical files and directories exist before attempting to start
mkdir -p "${FACTORIO_INSTALL_DIR}/saves"
mkdir -p "${FACTORIO_INSTALL_DIR}/config"

if [ ! -f "$FACTORIO_BIN" ]; then
    echo "Error: Factorio binary not found at $FACTORIO_BIN" >&2
    exit 1
fi

# If the save file doesn't exist, create it.
if [ ! -f "$SAVE_FILE_PATH" ]; then
    echo "Save file not found at ${SAVE_FILE_PATH}. Creating a new one..."
    "$FACTORIO_BIN" --create "$SAVE_FILE_PATH"
fi

if [ ! -f "$SERVER_SETTINGS_PATH" ]; then
    echo "Error: Server settings file not found at $SERVER_SETTINGS_PATH" >&2
    exit 1
fi

# --- Server Launch ---
echo "Starting Factorio server on port $SERVER_PORT..."
nohup "$FACTORIO_BIN" \
    --port "$SERVER_PORT" \
    --start-server "$SAVE_FILE_PATH" \
    --server-settings "$SERVER_SETTINGS_PATH" \
    >/dev/null 2>&1 &

# Output status
if [ $? -eq 0 ]; then
    echo "Factorio server started successfully."
else
    echo "Failed to start Factorio server."
    exit 1
fi