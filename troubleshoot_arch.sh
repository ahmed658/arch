#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Identify partitions
echo "Identifying partitions..."
lsblk
echo "Success: Partitions identified."

# Import ZFS pool
echo "Importing ZFS pool..."
zpool import -f zroot
echo "Success: ZFS pool imported."

# Mount ZFS root partition
echo "Mounting ZFS root partition..."
mount -t zfs zroot/ROOT/default /mnt
echo "Success: ZFS root partition mounted."

# Mount EFI partition
echo "Mounting EFI partition..."
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
echo "Success: EFI partition mounted."

# Chroot into the installed system
echo "Chrooting into the installed system..."
arch-chroot /mnt <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
echo "Success: Timezone set."

# Localization
sed -i 's/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_GB.UTF-8' > /etc/locale.conf
echo "Success: Localization set."

# Network Configuration
echo 'Small Brother' > /etc/hostname
cat <<EOT >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   Small Brother.localdomain Small Brother
EOT
echo "Success: Network configuration set."

# Keyboard layout
echo "KEYMAP=us" > /etc/vconsole.conf
echo "Success: Keyboard layout set."

# Configure initramfs for ZFS
sed -i 's/^HOOKS.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P
echo "Success: Initramfs configured for ZFS."

# Set root password
echo "root:AcerPowerF#1" | chpasswd
echo "Success: Root password set."

# Set ZFS configurations
zpool set cachefile=/etc/zfs/zpool.cache zroot
zpool set bootfs=zroot/ROOT/default zroot
systemctl enable zfs-import-cache zfs-import.target zfs-mount zfs-zed zfs.target
echo "Success: ZFS configurations set."

# Install ZFS Boot Menu
mkdir -p /boot/efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /boot/efi/EFI/zbm/zfsbootmenu.EFI
efibootmgr --disk /dev/nvme0n1 --part 1 --create --label "ZFSBootMenu" --loader '\EFI\zbm\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
echo "Success: ZFS Boot Menu installed."

EOF

# Unmount and export ZFS pool
echo "Unmounting and exporting ZFS pool..."
umount /mnt/boot
zpool export zroot
echo "Success: ZFS pool unmounted and exported."

echo "Checks complete! You can now reboot."
