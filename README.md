# Factorio Server Updater

[![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)

A Bash script for automatically updating a headless Factorio server on Linux to the latest stable version.

This script is designed to be run manually or automated as a cron job. It handles stopping the server, backing up essential data, installing the new version, restoring data, and restarting the server.

**In case of anything unpleasant, always back up your server before using this script for the first time.**

## How does the script work?

The script follows a safe and logical sequence to ensure a smooth update process:

- **Load Configuration**: It begins by reading your custom settings from the `factorio_updater.conf` file.
- **Check for Updates**: It contacts the official Factorio API to fetch the version number of the latest stable headless release.
- **Compare Versions**: It compares the latest available version with the version currently installed (recorded in `logs/current_version.txt`).
- **Execute Update (if needed)**: If a newer version is found, the script proceeds with the following steps:
    1.  **Stop Server**: It sends a `SIGTERM` shutdown signal to the running Factorio process and waits for it to exit. If the server is unresponsive, it will use a `SIGKILL` to force it to stop. **Note: The script will attempt to shut down the server even if players are online.**
    2.  **Backup Data**: If `PERFORM_BACKUP_RESTORE` is `true`, it creates a timestamped backup of your `saves` and `config` directories.
    3.  **Download New Version**: It downloads the latest version archive (`.tar.xz`) from the official Factorio download server.
    4.  **Extract Files**: It extracts the new files, overwriting the old Factorio installation.
    5.  **Restore Data**: If `PERFORM_BACKUP_RESTORE` is `true`, it copies your saves and configuration files from the temporary backup into the newly updated directory structure.
    6.  **Update Version Record**: It writes the new version number to `logs/current_version.txt`.
    7.  **Clean Up**: It removes the downloaded server archive and the temporary backup directory.
    8.  **Restart Server**: Finally, it executes your `start_factorio_server.sh` to bring the server back online with the new version.
- **No Action**: If the script finds you are already on the latest version, it will log a message and exit. As a bonus, if it finds the server is up-to-date but not running, it will attempt to start it.

## Prerequisites

Before using this script, ensure the following tools are available on your server:

- `bash`: The script is written for Bash.
- `curl`: Used to communicate with the Factorio API.
- `wget`: Used to download the Factorio tarball.
- `tar`: Used to extract the downloaded archive.
- `jq` (Highly Recommended): A command-line JSON processor for reliably parsing the API response. If `jq` is not found, the script will use a less reliable `grep`/`sed` fallback.

## Installation

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/your-username/factorio-server-updater.git](https://github.com/your-username/factorio-server-updater.git)
    cd factorio-server-updater
    ```
2.  **Make the Scripts Executable:**
    ```bash
    chmod +x update_factorio.sh
    chmod +x start_factorio_server.sh
    ```

## Configuration

### 1. Main Configuration

All primary configuration is handled in the `factorio_updater.conf` file. Edit the variables in this file to match your local environment before running the updater script.

### 2. Start Script Configuration

The updater relies on `start_factorio_server.sh` to launch your server. You must **edit this file** to ensure it points to the correct save file and uses the desired server settings. This script is designed to read all its path information from `factorio_updater.conf`, so you typically only need to confirm the `SAVE_FILE_NAME` and `SERVER_PORT` variables in the `.conf` file are correct.

## Usage

### Basic Execution

To run the update process manually, simply execute the script:
```bash
./update_factorio.sh
```
By default, this will run silently (no screen output) and log all actions to the log file.

## Debug Mode
For verbose output, use the `--debug` or `-d` flag. This will print all standard and debug messages to your screen while also writing them to the log file. This is useful for troubleshooting.
```bash
./update_factorio.sh --debug
```

## Dry Run Mode
To simulate an update without making any changes or test configuration, use the --dry-run flag. This will:
+ Print all actions to the screen, just like debug mode.
+ Check for new versions, perform backups, and download the new files.
+ This **WILL NOT** stop your server, extract files, restore backups, or restart the server.
+ The downloaded archive and backup folder will be left for you to inspect.

This is the safest way to test your configuration and see what the script would do.

```bash
./update_factorio.sh --dry-run
```

## Automation with Cron (Recommended)
The best way to use this script is to automate it with a cron job.
1. Open your crontab for editing: `crontab -e`
2. Add the following line to run the script at a set interval. This example runs the script every day at 4:00 AM.
```
# Check for Factorio updates daily at 4:00 AM
0 4 * * * /path/to/your/repo/factorio-server-updater/update_factorio.sh
```
Replace `/path/to/your/repo/` with the absolute path to where you cloned the repository.

## Logging
The script creates a `logs` directory inside the repository folder.
+ `logs/factorio_update.log`: All script output is logged here. This is the first place to look if something goes wrong.
+ `logs/current_version.txt`: This file stores the version number of the currently installed server in your local PC.

