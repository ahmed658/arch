#!/bin/bash

# Install base system
echo "Installing base system packages (this may take a while)..."
pacstrap /mnt base linux-lts linux-firmware linux-lts-headers wget nano efibootmgr
echo "Base system packages installed successfully."
confirm

# Install ZFS packages
echo "Installing ZFS packages..."
pacstrap /mnt zfs-dkms
echo "ZFS packages installed successfully."
confirm
