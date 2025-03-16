```bash
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
echo "Please select two disks for your ZFS striped setup:"

# Get list of disks
IFS=$'\n' read -d '' -r -a disks <<< "$(lsblk -d -n -o NAME)"

# Show the available disks
for i in "${!disks[@]}"; do
  echo "$i: ${disks[$i]}"
done

# Get the first disk
read -p "Enter the number for the FIRST disk: " disk1_number
DISK1="/dev/${disks[$disk1_number]}"
echo "Selected first disk: $DISK1"

# Get the second disk
read -p "Enter the number for the SECOND disk: " disk2_number
DISK2="/dev/${disks[$disk2_number]}"
echo "Selected second disk: $DISK2"

# Verify the disks exist
if [ ! -e "$DISK1" ]; then
  echo "Error: Disk $DISK1 does not exist!"
  exit 1
fi

if [ ! -e "$DISK2" ]; then
  echo "Error: Disk $DISK2 does not exist!"
  exit 1
fi

# Set fixed partition sizes
efi_size="2G"
zfs_size="50G"

echo "The following partitions will be created on each disk:"
echo " - EFI partition: $efi_size"
echo " - ZFS partition: $zfs_size (will be striped for a total of 100G)"

echo "WARNING: All data on $DISK1 and $DISK2 will be destroyed!"
echo "Are you sure you want to continue? (Type YES to confirm)"
read confirm
if [ "$confirm" != "YES" ]; then
  echo "Operation cancelled."
  exit 1
fi

# Partition the first disk
echo "Partitioning first disk $DISK1..."
sgdisk --zap-all "$DISK1"
sgdisk -n1:1M:+${efi_size} -t1:EF00 "$DISK1"
sgdisk -n2:0:+${zfs_size} -t2:BF00 "$DISK1"
echo "First disk partitioning completed successfully."

# Partition the second disk
echo "Partitioning second disk $DISK2..."
sgdisk --zap-all "$DISK2"
sgdisk -n1:1M:+${efi_size} -t1:EF00 "$DISK2"
sgdisk -n2:0:+${zfs_size} -t2:BF00 "$DISK2"
echo "Second disk partitioning completed successfully."

# Display partition tables
echo "Displaying partition table for $DISK1..."
sgdisk -p "$DISK1"
echo "Displaying partition table for $DISK2..."
sgdisk -p "$DISK2"

# Ensure disk partitions are detected
echo "Waiting for partition updates to be detected by the system..."
sleep 5
partprobe "$DISK1"
partprobe "$DISK2"
sleep 5

# Get partition names
DISK1_PART1="${DISK1}1"
DISK1_PART2="${DISK1}2"
DISK2_PART1="${DISK2}1"
DISK2_PART2="${DISK2}2"

# Check if partition naming needs adjustment (e.g., for NVMe drives)
if [[ "$DISK1" == *"nvme"* ]]; then
  DISK1_PART1="${DISK1}p1"
  DISK1_PART2="${DISK1}p2"
fi

if [[ "$DISK2" == *"nvme"* ]]; then
  DISK2_PART1="${DISK2}p1"
  DISK2_PART2="${DISK2}p2"
fi

# Verify partitions exist
echo "Verifying partitions..."
if [ ! -e "$DISK1_PART1" ] || [ ! -e "$DISK1_PART2" ] || [ ! -e "$DISK2_PART1" ] || [ ! -e "$DISK2_PART2" ]; then
  echo "Error: Some partitions not detected."
  echo "Expected: $DISK1_PART1, $DISK1_PART2, $DISK2_PART1, $DISK2_PART2"
  echo "Please check the partition naming convention for your disks."
  ls -la /dev/disk/by-id/
  ls -la /dev/
  exit 1
fi
echo "All partitions verified successfully."

# Create ZFS pool with STRIPED (not mirrored) data partitions
echo "Creating ZFS pool with STRIPED vdevs..."
zpool create -f -o ashift=12 \
 -O compression=zstd \
 -O acltype=posixacl \
 -O xattr=sa \
 -O relatime=on \
 -o autotrim=on \
 -m none zroot "$DISK1_PART2" "$DISK2_PART2"
sleep 5

# Verify pool creation
zpool status zroot
echo "ZFS pool created successfully with striping (RAID0)."
sleep 3

# Create ZFS datasets
echo "Creating ZFS datasets..."
zfs create -o mountpoint=none zroot/ROOT
sleep 3
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/arch
sleep 3
zfs create -o mountpoint=/Data zroot/Data
zfs list
echo "ZFS datasets created successfully."

# Export and re-import the pool
echo "Exporting and reimporting ZFS pool..."
zpool export zroot
sleep 3
zpool import -N -R /mnt zroot
echo "ZFS pool exported and reimported successfully."
sleep 3

# Mount the datasets
echo "Mounting ZFS datasets..."
zfs mount zroot/ROOT/arch
sleep 3
zfs mount zroot/Data
mount | grep zroot
echo "ZFS datasets mounted successfully."
sleep 3

# Format and mount the EFI partitions (we'll use the first one as primary)
echo "Formatting and mounting EFI partitions..."
mkdir -p /mnt/efi
mkfs.vfat -F 32 -n EFI1 "$DISK1_PART1"
mkfs.vfat -F 32 -n EFI2 "$DISK2_PART1"
sleep 3
mount "$DISK1_PART1" /mnt/efi
mkdir -p /mnt/efi2
mount "$DISK2_PART1" /mnt/efi2
mount | grep efi
echo "EFI partitions formatted and mounted successfully."

# Install base system
echo "Installing base system packages (this may take a while)..."
pacstrap /mnt base linux-lts linux-firmware linux-lts-headers wget nano efibootmgr intel-ucode nvidia-open-lts nvidia-utils networkmanager
echo "Base system packages installed successfully."

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt > /mnt/etc/fstab
echo "Editing fstab to keep only the EFI partition lines..."
grep "/efi" /mnt/etc/fstab > /tmp/efi_lines
cat /tmp/efi_lines > /mnt/etc/fstab
echo "New fstab:"
cat /mnt/etc/fstab

# First part of the chroot setup (key import and package installation)
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

# Add Chaotic AUR if not already added
if ! grep -q 'chaotic-aur' /etc/pacman.conf; then
  pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
  pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  echo '[chaotic-aur]' | tee -a /etc/pacman.conf
  echo 'Include = /etc/pacman.d/chaotic-mirrorlist' | tee -a /etc/pacman.conf
  echo "Chaotic AUR repository added successfully."
else
  echo "Chaotic AUR repository already configured."
fi

# Verify Chaotic AUR configuration
echo "Verifying Chaotic AUR configuration..."
grep 'chaotic-aur' /etc/pacman.conf
echo "Chaotic AUR configuration verification completed."

# Update the system and install ZFS packages
echo "Updating system packages and installing ZFS..."
pacman -Syu --noconfirm zfs-dkms zfs-utils
echo "System update and ZFS installation completed successfully."
EOF

# Final chroot setup with system configuration
arch-chroot /mnt /bin/bash <<EOF
#!/bin/bash

# Set timezone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
echo "Timezone set to Europe/London."

# Configure locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "Locale configured to en_US.UTF-8."

# Set hostname
hostname="SmallBrother"
echo "\$hostname" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 \$hostname" >> /etc/hosts
echo "Hostname set to \$hostname."

# Configure initramfs
sed -i '/^HOOKS=/ s/\bblock\b/block zfs/' /etc/mkinitcpio.conf
sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkinitcpio -P
echo "Initramfs configured with ZFS and NVIDIA modules."

# Set root password
echo "root:AcerPowerF#1" | chpasswd
echo "Root password set."

# Configure ZFS boot
zpool set bootfs=zroot/ROOT/arch zroot
systemctl enable zfs-import-cache
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs-zed
systemctl enable zfs.target
systemctl enable NetworkManager
echo "ZFS boot services and NetworkManager enabled."

# Set up ZFSBootMenu on both EFI partitions
mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zbm/zfsbootmenu.EFI
echo "ZFSBootMenu installed to primary EFI partition."

# Copy to second EFI partition
mkdir -p /efi2/EFI/zbm
cp /efi/EFI/zbm/zfsbootmenu.EFI /efi2/EFI/zbm/
echo "ZFSBootMenu copied to secondary EFI partition."

# Create EFI boot entries for both disks
DISK1="$DISK1"
DISK2="$DISK2"

# Adjust for NVMe naming if necessary
if [[ "\$DISK1" == *"nvme"* ]]; then
  PART_NUM="p1"
else
  PART_NUM="1"
fi

# Create primary bootloader entry
efibootmgr --disk "\$DISK1" --part \${PART_NUM#p} --create --label "ZFSBootMenu-Primary" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose

if [[ "\$DISK2" == *"nvme"* ]]; then
  PART_NUM="p1"
else
  PART_NUM="1"
fi

# Create secondary bootloader entry
efibootmgr --disk "\$DISK2" --part \${PART_NUM#p} --create --label "ZFSBootMenu-Backup" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose

echo "EFI boot entries created for both disks."

# Set ZFS command line
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 nvidia-drm.modeset=1 nvidia-drm.fbdev=1 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
echo "ZFS command line set with NVIDIA parameters."

# Final system check
echo "Checking ZFS pool status..."
zpool status
echo "Checking ZFS datasets..."
zfs list
echo "System configuration completed successfully!"
EOF

# Unmount and clean up
echo "Unmounting filesystems and exporting ZFS pool..."
umount /mnt/efi
umount /mnt/efi2
zfs unmount -a
zpool export zroot
echo "Installation complete! The system is ready to reboot."
echo "You can now safely reboot into your new ZFS striped system."
echo ""
echo "NOTE: A STRIPED setup (RAID0) increases performance and storage capacity but provides NO redundancy."
echo "If either disk fails, ALL DATA WILL BE LOST. Make sure you have a robust backup strategy!"
```
