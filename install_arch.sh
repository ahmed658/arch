#!/bin/bash

# Check and import key if not already done
if ! pacman-key --list-keys 3056513887B78AEB &>/dev/null; then
  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
fi

# Install Chaotic AUR keyring and mirror list if not already done
if ! grep -q 'chaotic-aur' /etc/pacman.conf; then
  sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
  sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  echo '[chaotic-aur]' | sudo tee -a /etc/pacman.conf
  echo 'Include = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf
fi

# Update the system
sudo pacman -Syu

# Generate and set hostid
if [ ! -f /etc/hostid ]; then
  sudo zgenhostid
fi

# Ensure EFI partition is formatted and mounted
DISK=/dev/nvme0n1
EFI_PART=${DISK}p1
if ! mount | grep -q '/mnt/efi'; then
  sudo mkfs.vfat -F 32 -n EFI $EFI_PART
  sudo mkdir -p /mnt/efi
  sudo mount $EFI_PART /mnt/efi
fi

# Install base system and tools
sudo pacstrap /mnt base linux-lts linux-firmware linux-lts-headers wget nano vim efibootmgr

# Install ZFS support
sudo pacstrap /mnt zfs-dkms

# Copy necessary files
sudo cp /etc/hostid /mnt/etc
sudo cp /etc/resolv.conf /mnt/etc
sudo mkdir -p /mnt/etc/zfs
sudo cp /etc/pacman.conf /mnt/etc/pacman.conf

# Generate and edit fstab
sudo genfstab /mnt > /mnt/etc/fstab
sudo sed -i '/^\/mnt\/efi/!d' /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc

# Localization
sed -i 's/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_GB.UTF-8' > /etc/locale.conf

# Network Configuration
echo 'Small Brother' > /etc/hostname
cat <<EOT >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   Small Brother.localdomain Small Brother
EOT

# Keyboard layout
echo "KEYMAP=us" > /etc/vconsole.conf

# Configure initramfs for ZFS
sed -i 's/^HOOKS.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "AcerPowerF#1" | passwd --stdin

# Set ZFS configurations
zpool set cachefile=/etc/zfs/zpool.cache zroot
zpool set bootfs=zroot/ROOT/arch zroot
systemctl enable zfs-import-cache zfs-import.target zfs-mount zfs-zed zfs.target

# Install ZFS Boot Menu
mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zbm/zfsbootmenu.EFI
efibootmgr --disk $DISK --part 1 --create --label "ZFSBootMenu" --loader '\EFI\zbm\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=\$(hostid)" zroot/ROOT

EOF

# Unmount and export ZFS pool
sudo umount /mnt/efi
sudo zpool export zroot

echo "Installation complete! You can now reboot."
