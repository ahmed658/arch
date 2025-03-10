#!/bin/bash

# Function to confirm proceeding
confirm() {
  read -r -p "Proceed with the next step? (type 'yes' to continue) " response
  if [ "$response" != "yes" ]; then
    echo "Operation cancelled by user."
    exit 1
  fi
}

# Create log file
LOG_FILE="zfs_install_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"

# Function to log commands and their outputs
log_cmd() {
  echo "Running: $@"
  "$@"
  local status=${PIPESTATUS[0]}
  if [ $status -ne 0 ]; then
    echo "Command failed with status $status. Exiting."
    exit $status
  fi
  return $status
}

echo "Starting ZFS installation script at $(date)"
echo "Logging all output to $LOG_FILE"

# Check and import key if not already done
if ! pacman-key --list-keys 3056513887B78AEB &>/dev/null; then
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
  echo "Key import completed successfully."
else
  echo "Key already imported."
fi
confirm

# Verify key import
echo "Verifying key import..."
pacman-key --list-keys 3056513887B78AEB
echo "Key verification completed."
confirm
