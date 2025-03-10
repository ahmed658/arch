#!/bin/bash

# Export and re-import the pool
echo "Exporting and reimporting ZFS pool..."
zpool export zroot
zpool import -N -R /mnt zroot
echo "ZFS pool exported and reimported successfully."
confirm

# Mount the datasets
echo "Mounting ZFS datasets..."
zfs mount zroot/ROOT/arch
zfs mount zroot/Data
mount | grep zroot
echo "ZFS datasets mounted successfully."
confirm

# Format and mount the EFI partition
echo "Formatting and mounting EFI partition..."
mkfs.vfat -F 32 -n EFI "${DISK}-part1"
mkdir -p /mnt/efi
mount "${DISK}-part1" /mnt/efi
mount | grep efi
echo "EFI partition formatted and mounted successfully."
confirm
