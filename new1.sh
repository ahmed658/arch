#!/bin/bash

# Log file
LOGFILE="/var/log/arch_install.log"
exec > >(tee -i $LOGFILE)
exec 2>&1

# List available disks and prompt user to choose one
echo "Available disks:"
lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme|/dev/vd"
echo "Enter the disk to install Arch Linux (e.g., /dev/sda): "
read DISK

# Confirm the selected disk
echo "You have chosen to install on $DISK. All data on this disk will be erased. Continue? (y/n)"
read CONFIRM
if [[ $CONFIRM != "y" ]]; then
  echo "Installation aborted."
  exit 1
fi

# Set up keyboard, layout, and locale
loadkeys us
timedatectl set-ntp true

# Delete previous partitions
echo "Deleting previous partitions on $DISK..."
sgdisk -Z $DISK

# Partition the disk
echo "Creating partitions on $DISK..."
sgdisk -o $DISK
sgdisk -n1:1M:+2G -t1:EF00 $DISK
sgdisk -n2:0:+50G -t2:BF01 $DISK
mkfs.vfat -F32 ${DISK}1
modprobe zfs
zpool create -f -o ashift=12 -O atime=off -O relatime=on -O normalization=formD -O mountpoint=none rpool ${DISK}2
zfs create -o mountpoint=none rpool/ROOT
zfs create -o mountpoint=/ rpool/ROOT/default

# Mount the file systems
echo "Mounting file systems..."
mount -t zfs rpool/ROOT/default /mnt
mkdir /mnt/boot
mount ${DISK}1 /mnt/boot

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux-lts linux-firmware zfs-dkms zfs-utils

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Entering chroot..."
arch-chroot /mnt

# Set up time zone
echo "Setting up time zone..."
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

# Localization
echo "Setting up localization..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "Configuring network..."
echo "myhostname" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 myhostname.localdomain myhostname" >> /etc/hosts

# Set root password
echo "Setting root password..."
echo "root:password" | chpasswd

# Install essential packages
echo "Installing essential packages..."
pacman -S zfsbootmenu efibootmgr networkmanager

# Install ZFSBootMenu
echo "Installing ZFSBootMenu..."
cat <<EOF > /etc/zfsbootmenu/config.yaml
Global:
  ManageImages: true
  BootMountPoint: /boot
Components:
  Image: /boot/vmlinuz-linux-lts
  Initramfs: /boot/initramfs-linux-lts.img
  FallbackInitramfs: /boot/initramfs-linux-lts-fallback.img
EOF

echo "Creating initramfs..."
mkinitcpio -P

# Enable NetworkManager
echo "Enabling NetworkManager..."
systemctl enable NetworkManager

# Exit chroot and reboot
echo "Exiting chroot and rebooting..."
exit
umount -R /mnt
reboot
