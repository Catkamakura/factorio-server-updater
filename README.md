# factorio-server-updater

[![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)

A Bash script for automatically updating a headless Factorio server on Linux to the latest stable version.

This script is designed to be run manually or automated as a cron job. It handles stopping the server, backing up essential data, installing the new version, restoring data, and restarting the server.

**In case of anything unpleasant, Backup your server before using this script. **

## How does the script work?

+ Load Configuration: It begins by reading your custom settings from the ```factorio_updater.conf```+
+  Check for Updates: It checks whether a new version is available via the official Factorio API
+ Compare Versions: It compares the latest available version with the version currently installed (recorded in ```current_version.txt```)
+ Execute Update (if needed): If a newer version is found, the script proceeds with the following steps:
   1. Stop Server: It sends a ```SIGTERM``` shutdown signal to the running Factorio process and waits for its exit. If the server is unresponsive, it will use a SIGKILL to force it to stop. **Please note the script will try to shutdown even if there's user(player) online**
   2. Backup Data: If ```PERFORM_BACKUP_RESTORE``` is ```true```, it creates a timestamped backup of your saves and config directories.
   3. Download New Version: It downloads the least version archive (.tar.xz) using the link provided (default: ```https://factorio.com/get-download/stable/headless/linux64```)
   4. Extract Files: It extracts the new files, overwriting the old Factorio installation
   5. Restore Data: If ```PERFORM_BACKUP_RESTORE``` is ```true```, it copies your saves and configuration files from the temporary backup into the newly updated directory structure
   6. Update Version Record: It writes the new version number to ```current_version.txt```
   7. Clean Up: It removes the downloaded server archive and the temporary backup directory.
   8. Restart Server: Finally, it executes a ```start_factorio_server.sh``` to bring the server back online with the new version
+ No Action: If the script finds you are already on the latest version, it will log a message and exit. As a bonus, if it finds the server is up-to-date but not running, it will attempt to start it.
## Prerequisites

Before using this script, ensure the following tools are available on your server:

-   `bash`: The script is written for Bash.
-   `curl`: Used to communicate with the Factorio API.
-   `wget`: Used to download the Factorio tarball.
-   `tar`: Used to extract the downloaded archive.
-   `jq` (Highly Recommended): A command-line JSON processor. The script uses it for reliably parsing the API response. If `jq` is not found, the script will attempt to use a less reliable `grep`/`sed` fallback.

## Configuration

All configuration is handled in the ```factorio_updater.conf``` file. Edit it based on your local environment before run the updater script.

## Run the Updater

1. Make the script executable:
```
chmod +x update_factorio.sh
```
2. Manually run the updater:
```
update_factorio.sh
```
3. Automate with Cron (Recommended): The best way to use this script is to automate it with a cron job.
+ Open your crontab for editing: ```crontab -e```\
+ Add the following line to run the script at a set interval. This example runs the script every day at 4:00 AM.
  ```
  # Check for Factorio updates daily at 4:00 AM
  0 4 * * * /path/to/your/repo/factorio-server-updater/update_factorio.sh
  ```
## Logging
The script logs all its output to ```factorio_update.log```, located in the FACTORIO_BASE_DIR you defined in the configuration. This is the first place you should look if something goes wrong.
