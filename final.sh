#!/bin/bash

# Generate host ID
echo "Generating host ID..."
zgenhostid
echo "Host ID generated successfully: $(hostid)"

# Verify host ID generation
echo "Verifying host ID generation..."
hostid
echo "Host ID verification completed."

# List available disks
echo "Listing available disks..."
lsblk -d -n -o NAME,SIZE
echo "Please select a disk by typing the number corresponding to the list (e.g., 0 for sda, 1 for sdb):"
IFS=$'\n' read -d '' -r -a disks <<< "$(lsblk -d -n -o NAME)"

for i in "${!disks[@]}"; do
  echo "$i: ${disks[$i]}"
done

read -p "Enter the disk number: " disk_number
DISK="/dev/${disks[$disk_number]}"
echo "Selected disk: $DISK"

# Verify the disk exists
if [ ! -e "$DISK" ]; then
  echo "Error: Disk $DISK does not exist!"
fi

echo "WARNING: All data on $DISK will be destroyed!"

# Partition the disk
echo "Partitioning disk $DISK..."
sgdisk --zap-all "$DISK"
sgdisk -n1:1M:+2G -t1:EF00 "$DISK"
sgdisk -n2:0:+50G -t2:BF00 "$DISK"
echo "Disk partitioning completed successfully."

# Display partition table
echo "Displaying partition table for $DISK..."
sgdisk -p "$DISK"
echo "Partition table display completed."

# Ensure disk partitions are detected
echo "Waiting for partition updates to be detected by the system..."
sleep 30
if [ ! -e "${DISK}-part1" ] || [ ! -e "${DISK}-part2}" ]; then
  echo "Error: Disk partitions not detected. Please check if ${DISK}-part1 and ${DISK}-part2 exist."
fi


# Create ZFS pool
echo "Creating ZFS pool..."
zpool create -f -o ashift=12 \
 -O compression=zstd \
 -O acltype=posixacl \
 -O xattr=sa \
 -O relatime=on \
 -o autotrim=on \
 -m none zroot "/dev/nvme0n1p2"
sleep 10

# Verify pool creation
zpool status zroot
echo "ZFS pool created successfully."
sleep 10

# Create ZFS datasets
echo "Creating ZFS datasets..."
zfs create -o mountpoint=none zroot/ROOT
sleep 10
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/arch
sleep 10
zfs create -o mountpoint=/Data zroot/Data
zfs list
echo "ZFS datasets created successfully."

# Export and re-import the pool
echo "Exporting and reimporting ZFS pool..."
zpool export zroot
sleep 10
zpool import -N -R /mnt zroot
echo "ZFS pool exported and reimported successfully."
sleep 10

# Mount the datasets
echo "Mounting ZFS datasets..."
zfs mount zroot/ROOT/arch
sleep 10
zfs mount zroot/Data
mount | grep zroot
echo "ZFS datasets mounted successfully."
sleep 10

# Format and mount the EFI partition
echo "Formatting and mounting EFI partition..."
mkfs.vfat -F 32 -n EFI "/dev/nvme0n1p1"
sleep 10
mkdir -p /mnt/efi
mount "/dev/nvme0n1p1" /mnt/efi
mount | grep efi
echo "EFI partition formatted and mounted successfully."

# Install base system
echo "Installing base system packages (this may take a while)..."
pacstrap /mnt base linux-lts linux-firmware linux-lts-headers wget nano efibootmgr intel-ucode nvidia-open-lts nvidia-utils networkmanager
echo "Base system packages installed successfully."

echo "Original fstab:"
cat /mnt/etc/fstab
echo ""
echo "Keeping only the EFI partition line..."
grep "/efi" /mnt/etc/fstab > /tmp/new_fstab
mv /tmp/new_fstab /mnt/etc/fstab
echo "New fstab:"
cat /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
# Check and import key if not already done
if ! pacman-key --list-keys 3056513887B78AEB &>/dev/null; then
   pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
   pacman-key --lsign-key 3056513887B78AEB
  echo "Key import completed successfully."
else
  echo "Key already imported."
fi

# Verify key import
echo "Verifying key import..."
pacman-key --list-keys 3056513887B78AEB
echo "Key verification completed."
if ! grep -q 'chaotic-aur' /etc/pacman.conf; then
   pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
   pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  echo '[chaotic-aur]' |  tee -a /etc/pacman.conf
  echo 'Include = /etc/pacman.d/chaotic-mirrorlist' |  tee -a /etc/pacman.conf
  echo "Chaotic AUR repository added successfully."
else
  echo "Chaotic AUR repository already configured."
fi

# Verify Chaotic AUR configuration
echo "Verifying Chaotic AUR configuration..."
grep 'chaotic-aur' /etc/pacman.conf
echo "Chaotic AUR configuration verification completed."

# Update the system
echo "Updating system packages..."
 pacman -Syu --noconfirm zfs-dkms zfs-utils
echo "System update completed successfully."
EOF

arch-chroot /mnt /bin/bash <<EOF
#!/bin/bash

# Set timezone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc

# Configure locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Set hostname
hostname="SmallBrother"
echo "\$hostname" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 \$hostname" >> /etc/hosts

# Configure initramfs
sed -i '/^HOOKS=/ s/\bblock\b/block zfs/' /etc/mkinitcpio.conf
sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "root:AcerPowerF#1" | chpasswd

# Configure ZFS boot
zpool set bootfs=zroot/ROOT/arch zroot
systemctl enable zfs-import-cache
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs-zed
systemctl enable zfs.target

mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zfsbootmenu.EFI

DISK="/dev/nvme0n1"
efibootmgr --disk \$DISK --part 1 --create --label "ZFSBootMenu" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 nvidia-drm.modeset=1 nvidia-drm.fbdev=1 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
EOF
