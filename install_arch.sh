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

# Generate host ID
zgenhostid

# Define disk
DISK=/dev/disk/by-id/nvme0n1

# Partition the disk
sgdisk --zap-all $DISK
sgdisk -n1:1M:+512M -t1:EF00 $DISK
sgdisk -n2:0:0 -t2:BF00 $DISK

# Create ZFS pool
zpool create -f -o ashift=12 \
 -O compression=zstd \
 -O acltype=posixacl \
 -O xattr=sa \
 -O relatime=on \
 -o autotrim=on \
 -m none zroot ${DISK}-part2

# Create ZFS datasets
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/arch
zfs create -o mountpoint=/Data zroot/Data

# Export and re-import the pool
zpool export zroot
zpool import -N -R /mnt zroot
zfs mount zroot/ROOT/arch
zfs mount zroot/Data

# Format and mount the EFI partition
mkfs.vfat -F 32 -n EFI $DISK-part1
mkdir /mnt/efi
mount $DISK-part1 /mnt/efi

# Install base system
pacstrap /mnt base linux-lts linux-firmware linux-lts-headers wget nano efibootmgr
pacstrap /mnt zfs-dkms

# Copy configuration files
cp /etc/hostid /mnt/etc
cp /etc/resolv.conf /mnt/etc
mkdir -p /mnt/etc/zfs
cp /etc/pacman.conf /mnt/etc/pacman.conf

# Generate fstab
genfstab /mnt > /mnt/etc/fstab
echo "# Edit /etc/fstab to keep only the line containing /efi" > /mnt/edit_fstab.sh
chmod +x /mnt/edit_fstab.sh

# Create a script to run inside the chroot
cat > /mnt/chroot_setup.sh << 'EOF'
#!/bin/bash

# Set timezone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc

# Uncomment needed locales
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Set hostname
read -p "Enter hostname: " hostname
echo "$hostname" > /etc/hostname
echo "127.0.0.1   localhost" > /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   $hostname" >> /etc/hosts

# Configure initramfs
sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "Set root password:"
passwd

# Configure ZFS boot
zpool set bootfs=zroot/ROOT/arch zroot
systemctl enable zfs-import-cache zfs-import.target zfs-mount zfs-zed zfs.target

# Set up ZFSBootMenu
mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zbm/zfsbootmenu.EFI

# Create EFI boot entry
disk_base=$(echo "$DISK" | sed 's/-part[0-9]*$//')
efibootmgr --disk $disk_base --part 1 --create --label "ZFSBootMenu" --loader '\EFI\zbm\zfsbootmenu.EFI' --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose

# Set ZFS command line
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=$(hostid)" zroot/ROOT
EOF

chmod +x /mnt/chroot_setup.sh

# Chroot into the system
echo "Now you will be chrooted into the new system to complete the setup."
echo "Run the script /chroot_setup.sh to continue the installation."
arch-chroot /mnt

# After exiting the chroot, unmount and reboot
umount /mnt/efi
zpool export zroot
echo "Installation complete. You can now reboot the system."
