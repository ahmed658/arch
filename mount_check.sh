#!/bin/bash

# Script to verify and mount necessary filesystems for troubleshooting ZFS Boot Menu and Arch Linux on ZFS

# Variables
ZPOOL_NAME="zroot"  # Replace with your ZFS pool name
EFI_PARTITION="/dev/disk/by-partlabel/EFI"  # Replace with your EFI partition
MOUNT_POINT="/mnt"

# Function to check if a filesystem is mounted
is_mounted() {
    mountpoint -q "$1"
}

# Function to wait for 3 seconds
wait_3_seconds() {
    echo "Waiting for 3 seconds..."
    sleep 3
}

# Function to confirm before mounting
confirm_mount() {
    local mount_point=$1
    local description=$2
    read -p "Mount $description at $mount_point? (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo "Skipping mount of $description."
        return 1
    fi
    return 0
}

# Force import the ZFS pool
echo "Force importing ZFS pool '$ZPOOL_NAME'..."
zpool import -f "$ZPOOL_NAME" || { echo "Failed to force import ZFS pool '$ZPOOL_NAME'"; exit 1; }
wait_3_seconds

# Mount the root filesystem
if is_mounted "$MOUNT_POINT"; then
    echo "ZFS root filesystem is already mounted at '$MOUNT_POINT'."
else
    if confirm_mount "$MOUNT_POINT" "ZFS root filesystem"; then
        echo "Mounting ZFS root filesystem to '$MOUNT_POINT'..."
        zfs mount "$ZPOOL_NAME/ROOT/arch" || { echo "Failed to mount ZFS root filesystem"; exit 1; }
        wait_3_seconds
    fi
fi

# Check and mount the EFI partition
EFI_MOUNT="$MOUNT_POINT/efi"
if is_mounted "$EFI_MOUNT"; then
    echo "EFI partition is already mounted at '$EFI_MOUNT'."
else
    if confirm_mount "$EFI_MOUNT" "EFI partition"; then
        echo "Mounting EFI partition to '$EFI_MOUNT'..."
        mkdir -p "$EFI_MOUNT"
        EFI_BLOCKDEV=$(readlink -f "$EFI_PARTITION")  # Look up the block device
        echo "EFI partition block device: $EFI_BLOCKDEV"
        mount "$EFI_BLOCKDEV" "$EFI_MOUNT" || { echo "Failed to mount EFI partition"; exit 1; }
        wait_3_seconds
    fi
fi

# Check and mount other critical filesystems (e.g., /boot, /var, etc.)
# Example for /boot (if using a separate dataset)
BOOT_MOUNT="$MOUNT_POINT/boot"
if zfs list "$ZPOOL_NAME/BOOT" &>/dev/null; then
    if is_mounted "$BOOT_MOUNT"; then
        echo "ZFS boot filesystem is already mounted at '$BOOT_MOUNT'."
    else
        if confirm_mount "$BOOT_MOUNT" "ZFS boot filesystem"; then
            echo "Mounting ZFS boot filesystem to '$BOOT_MOUNT'..."
            zfs mount "$ZPOOL_NAME/BOOT" || { echo "Failed to mount ZFS boot filesystem"; exit 1; }
            wait_3_seconds
        fi
    fi
else
    echo "ZFS boot filesystem dataset '$ZPOOL_NAME/BOOT' does not exist."
fi

# Verify all required filesystems are mounted
echo "Verifying mounted filesystems..."
df -h | grep -E "$MOUNT_POINT|$EFI_MOUNT|$BOOT_MOUNT"

echo "All required filesystems are mounted. You can now troubleshoot ZFS Boot Menu and Arch Linux on ZFS."
