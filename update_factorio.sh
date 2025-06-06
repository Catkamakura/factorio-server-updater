#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Initial Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOGS_DIR="${SCRIPT_DIR}/logs"
CONFIG_FILE="${SCRIPT_DIR}/factorio_updater.conf"
START_SCRIPT_PATH="${SCRIPT_DIR}/start_factorio_server.sh"
INSTALLED_VERSION_FILE="${LOGS_DIR}/current_version.txt"
LOG_FILE="${LOGS_DIR}/factorio_update.log"

# --- Argument Parsing ---
DEBUG_MODE=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    -d|--debug)
      DEBUG_MODE=true
      shift # Remove --debug from processing
      ;;
    --dry-run)
      DRY_RUN=true
      shift # Remove --dry-run from processing
      ;;
  esac
done

# Dry run forces debug output
if [ "$DRY_RUN" = true ]; then
    DEBUG_MODE=true
fi

# --- Logging & Directory Setup ---
# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Set up logging based on debug mode
if [ "$DEBUG_MODE" = true ]; then
    # In debug mode, tee output to both screen and log file
    exec > >(tee -a "${LOG_FILE}") 2>&1
else
    # In normal mode, redirect all output to log file only
    exec >> "${LOG_FILE}" 2>&1
fi

# --- Helper Functions ---
log_debug() {
    # Only print debug messages if debug mode is enabled
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: $1"
    fi
}

# --- File & Configuration Checks ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found at: ${CONFIG_FILE}" >&2
    exit 1
fi
if [ ! -f "$START_SCRIPT_PATH" ]; then
    echo "start_factorio_server.sh not found at: ${START_SCRIPT_PATH}" >&2
    exit 1
fi

# Source the configuration file
source "$CONFIG_FILE"

# --- Dynamic Path Configuration ---
FACTORIO_INSTALL_DIR="${FACTORIO_BASE_DIR}/factorio"
FACTORIO_BIN_PATH="${FACTORIO_INSTALL_DIR}/bin/x64/factorio"
SAVES_DIR="${FACTORIO_INSTALL_DIR}/saves"
CONFIG_DIR="${FACTORIO_INSTALL_DIR}/config"
SERVER_SETTINGS_FILE="${CONFIG_DIR}/server-settings.json"
CONFIG_INI_FILE="${CONFIG_DIR}/config.ini"
SERVER_ADMINLIST_FILE="${CONFIG_DIR}/server-adminlist.json"

# --- Logging & Directory Setup ---
# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

echo "======================================================"
echo "Factorio Server Update Script started at $(date)"
if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN MODE ENABLED ---"
fi
echo "Backup/Restore is currently: $(if [ "$PERFORM_BACKUP_RESTORE" = true ]; then echo "ENABLED"; else echo "DISABLED"; fi)"
echo "======================================================"

# --- Helper Functions (Continued) ---
get_latest_version_info() {
    echo "Fetching latest version information from Factorio API (factorio.com/api/latest-releases)..."
    local api_url="https://factorio.com/api/latest-releases"
    local latest_version="" latest_filename="" response_json="" curl_exit_code=0

    log_debug "Contacting API URL: $api_url"
    response_json=$(curl -sL --connect-timeout 10 -m 30 "$api_url")
    curl_exit_code=$?

    if [ $curl_exit_code -ne 0 ]; then
        echo "Error: curl command failed with exit code $curl_exit_code when trying to reach API: ${api_url}." >&2
        return 1
    fi
    if [ -z "$response_json" ]; then
        echo "Error: Received empty response from API: ${api_url}." >&2
        return 1
    fi
    log_debug "Raw API Response: $response_json"

    if command -v jq >/dev/null 2>&1; then
        log_debug "jq is available. Using jq to parse API response."
        latest_version=$(echo "$response_json" | jq -e -r '.stable.headless // .game.stable // .headless.stable')
        if [ $? -ne 0 ] || [ "$latest_version" = "null" ] || [ -z "$latest_version" ]; then
            echo "Warning: Could not extract stable headless version using jq with primary paths." >&2
            log_debug "jq attempt output was: '$latest_version'"
            latest_version=""
        else
            log_debug "Version extracted via jq: '$latest_version'"
        fi
    fi

    if [ -z "$latest_version" ]; then
        if ! command -v jq >/dev/null 2>&1; then
             echo "Warning: jq command not found. Attempting to parse API response with grep/sed (less reliable)." >&2
        else
             log_debug "jq parsing failed or didn't find version. Attempting grep/sed."
        fi
        local temp_version
        if echo "$response_json" | grep -q '"stable"'; then
            temp_version=$(echo "$response_json" | tr -d '\n\r' | sed -n 's/.*"stable":{[^}]*"headless":"\([^"]*\)".*/\1/p')
        fi
        if [ -n "$temp_version" ]; then
            latest_version="$temp_version"
            log_debug "Version from API (grep/sed fallback): '$latest_version'"
        else
            echo "Error: Could not extract stable headless version using grep/sed fallback from API response." >&2
            if ! command -v jq >/dev/null 2>&1; then echo "Info: Installing 'jq' is highly recommended." >&2; fi
        fi
    fi

    if [ -z "$latest_version" ]; then
        echo "Error: Failed to determine latest stable headless version from API." >&2
        return 1
    fi
    if ! [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._A-Za-z0-9-]+)*$ ]]; then
        echo "Error: Parsed version '$latest_version' does not look like a valid version string." >&2
        return 1
    fi

    latest_filename="factorio-headless_linux_${latest_version}.tar.xz"
    log_debug "API determined version: $latest_version, Filename: $latest_filename"
    echo "$latest_version $latest_filename"
    return 0
}

get_installed_version() {
    if [ -f "$INSTALLED_VERSION_FILE" ]; then cat "$INSTALLED_VERSION_FILE"; else echo "0.0.0"; fi
}

is_server_running() {
    if pgrep -f "^${FACTORIO_BIN_PATH}" > /dev/null; then return 0; else return 1; fi
}

stop_server() {
    echo "Attempting to stop Factorio server..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would stop the server process, but skipping."
        return 0
    fi

    local pid count max_wait_seconds=30
    pid=$(pgrep -f "^${FACTORIO_BIN_PATH}")
    if [ -n "$pid" ]; then
        echo "Factorio server PID: $pid. Sending SIGTERM."
        kill -15 "$pid"
        count=0
        while [ $count -lt $max_wait_seconds ]; do
            if ! is_server_running; then echo "Factorio server stopped (SIGTERM)." ; return 0; fi
            sleep 1; count=$((count + 1)); echo -n "."
        done
        echo # Newline after dots
        if is_server_running; then
            echo "Server unresponsive to SIGTERM. Sending SIGKILL."
            kill -9 "$pid"
            sleep 3
            if is_server_running; then echo "Error: Server PID $pid not stopped by SIGKILL." >&2; return 1;
            else echo "Factorio server stopped (SIGKILL)." ; return 0; fi
        fi
    else echo "Factorio server not found running." ; return 0; fi
}

version_compare() { # Args: v1 v2. Returns 0 for eq, 1 for v1>v2, 2 for v1<v2
    log_debug "version_compare: Entered function. Comparing v1='$1' and v2='$2'"
    if [ "$1" = "$2" ]; then
        log_debug "version_compare: Versions are equal. Returning 0."
        return 0
    fi
    local sorted_output printf_output sort_exit_status highest_ver
    printf_output=$(printf '%s\n%s' "$1" "$2")
    sorted_output=$(echo "$printf_output" | sort -V)
    sort_exit_status=$?
    if [ $sort_exit_status -ne 0 ]; then
        echo "ERROR version_compare: 'sort -V' command failed with status $sort_exit_status." >&2
        echo "Warning version_compare: Assuming v1 < v2 due to sort error, returning 2." >&2
        return 2
    fi
    if [ -z "$sorted_output" ]; then
        echo "ERROR version_compare: 'sort -V' produced empty output." >&2
        echo "Warning version_compare: Assuming v1 < v2 due to empty sort output, returning 2." >&2
        return 2
    fi
    highest_ver=$(echo "$sorted_output" | tail -n1)
    if [ "$1" = "$highest_ver" ]; then
        log_debug "version_compare: v1 ('$1') is the highest. Returning 1 (v1 > v2)."
        return 1
    else
        log_debug "version_compare: v1 ('$1') is not the highest. Returning 2 (v1 < v2)."
        return 2
    fi
}

# --- Main Script Logic ---
version_info_output=$(get_latest_version_info)
if [ $? -ne 0 ]; then echo "Failed to get latest version info. Aborting." >&2; exit 1; fi

read -r LATEST_VERSION LATEST_FILENAME <<< "$version_info_output"
if [ -z "$LATEST_VERSION" ] || [ -z "$LATEST_FILENAME" ]; then
    echo "Critical error: LATEST_VERSION or LATEST_FILENAME is empty." >&2
    log_debug "version_info_output was: '$version_info_output'"
    exit 1
fi

INSTALLED_VERSION=$(get_installed_version)
echo "Latest available Factorio version: $LATEST_VERSION"
echo "Currently installed Factorio version: $INSTALLED_VERSION"

if version_compare "$LATEST_VERSION" "$INSTALLED_VERSION"; then
    COMPARE_RESULT=0 # versions are equal
else
    COMPARE_RESULT=$? # 1 for v1>v2, 2 for v1<v2
fi
log_debug "version_compare call finished. Result: $COMPARE_RESULT ($LATEST_VERSION vs $INSTALLED_VERSION)"

if [ $COMPARE_RESULT -eq 1 ]; then # Update needed (LATEST_VERSION > INSTALLED_VERSION)
    echo "New version $LATEST_VERSION available. Current: $INSTALLED_VERSION. Starting update..."
    if is_server_running; then
        if ! stop_server; then echo "Failed to stop server. Aborting update." >&2; exit 1; fi
    else
        echo "Server is not running. Proceeding with update."
    fi

    TEMP_BACKUP_DIR=""
    if [ "$PERFORM_BACKUP_RESTORE" = true ]; then
        BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        TEMP_BACKUP_DIR="${FACTORIO_BASE_DIR}/factorio_update_backup_${BACKUP_TIMESTAMP}"
        mkdir -p "$TEMP_BACKUP_DIR/saves" "$TEMP_BACKUP_DIR/config"
        echo "Backing up essential files to $TEMP_BACKUP_DIR..."
        if [ -d "$SAVES_DIR" ] && [ "$(ls -A "$SAVES_DIR" 2>/dev/null)" ]; then cp -R "$SAVES_DIR/." "$TEMP_BACKUP_DIR/saves/"; echo "Backed up saves."; fi
        for conf_file in "$SERVER_SETTINGS_FILE" "$CONFIG_INI_FILE" "$SERVER_ADMINLIST_FILE"; do
            if [ -f "$conf_file" ]; then cp "$conf_file" "$TEMP_BACKUP_DIR/config/"; echo "Backed up $(basename "$conf_file")."; fi
        done
    fi

    echo "Downloading Factorio version $LATEST_VERSION..."
    DOWNLOADED_TARBALL_PATH="${FACTORIO_BASE_DIR}/${LATEST_FILENAME}"
    wget -q -O "$DOWNLOADED_TARBALL_PATH" "https://www.factorio.com/get-download/$LATEST_VERSION/headless/linux64"
    if [ $? -ne 0 ]; then
        echo "Error: Download failed." >&2
        if [ "$PERFORM_BACKUP_RESTORE" = true ] && [ -d "$TEMP_BACKUP_DIR" ]; then rm -rf "$TEMP_BACKUP_DIR"; fi
        exit 1
    fi
    echo "Download complete."

    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Skipping extraction, restoration, and version update."
    else
        echo "Extracting new version (will overwrite existing files)..."
        tar -xf "$DOWNLOADED_TARBALL_PATH" -C "$FACTORIO_BASE_DIR"
        if [ ! -d "$FACTORIO_INSTALL_DIR" ] || [ ! -f "$FACTORIO_BIN_PATH" ]; then
            echo "Error: Extraction failed or critical files missing." >&2; exit 1;
        fi
        echo "Extraction complete."

        if [ "$PERFORM_BACKUP_RESTORE" = true ]; then
            echo "Restoring essential files..."
            mkdir -p "$SAVES_DIR" "$CONFIG_DIR"
            if [ -d "$TEMP_BACKUP_DIR/saves" ] && [ "$(ls -A "$TEMP_BACKUP_DIR/saves/" 2>/dev/null)" ]; then cp -R "$TEMP_BACKUP_DIR/saves/." "$SAVES_DIR/"; echo "Restored saves."; fi
            for conf_file_basename in "$(basename "$SERVER_SETTINGS_FILE")" "$(basename "$CONFIG_INI_FILE")" "$(basename "$SERVER_ADMINLIST_FILE")"; do
                if [ -f "$TEMP_BACKUP_DIR/config/$conf_file_basename" ]; then cp "$TEMP_BACKUP_DIR/config/$conf_file_basename" "$CONFIG_DIR/"; echo "Restored $conf_file_basename."; fi
            done
        fi

        # Ensure server-adminlist.json exists for Factorio 2.0+
        v2_check=""
        if version_compare "$LATEST_VERSION" "2.0.0"; then v2_check=0; else v2_check=$?; fi
        if ([ "$v2_check" -eq 1 ] || [ "$v2_check" -eq 0 ]) && [ ! -f "$SERVER_ADMINLIST_FILE" ]; then
            echo "Factorio $LATEST_VERSION may require $SERVER_ADMINLIST_FILE. Creating default empty file."
            mkdir -p "$CONFIG_DIR"
            echo "[]" > "$SERVER_ADMINLIST_FILE"
        fi

        echo "$LATEST_VERSION" > "$INSTALLED_VERSION_FILE"
        echo "Successfully updated Factorio to version $LATEST_VERSION."
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Downloaded tarball and backups have been left for inspection."
    else
        if [ "$PERFORM_BACKUP_RESTORE" = true ] && [ -d "$TEMP_BACKUP_DIR" ]; then echo "Cleaning up backup directory..."; rm -rf "$TEMP_BACKUP_DIR"; fi
        rm -f "$DOWNLOADED_TARBALL_PATH"; echo "Cleaned up downloaded tarball."

        echo "Attempting to start the new Factorio server..."
        if [ -f "$START_SCRIPT_PATH" ]; then
            if bash "$START_SCRIPT_PATH"; then echo "Factorio server started."; else echo "Error starting Factorio server." >&2; fi
        else echo "Error: Start script $START_SCRIPT_PATH not found." >&2; fi
    fi

elif [ $COMPARE_RESULT -eq 0 ]; then # Already up to date
    echo "Factorio server is already up to date (Version: $INSTALLED_VERSION)."
    if ! is_server_running; then
        echo "Server not running. Attempting to start..."
        if [ "$DRY_RUN" = true ]; then
            echo "DRY RUN: Would start the server, but skipping."
        elif [ -f "$START_SCRIPT_PATH" ]; then
            if bash "$START_SCRIPT_PATH"; then echo "Factorio server started."; else echo "Error starting Factorio server." >&2; fi
        else echo "Error: Start script $START_SCRIPT_PATH not found." >&2; fi
    else echo "Server is running."; fi
else # Installed version is newer or other error
    echo "Installed version ($INSTALLED_VERSION) is newer than latest stable ($LATEST_VERSION). No action taken."
fi

echo "------------------------------------------------------"
if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN MODE FINISHED ---"
fi
echo "Factorio Server Update Script finished at $(date)"
echo "Log file: ${LOG_FILE}"
echo "======================================================"