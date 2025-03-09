#!/bin/bash

# Create log file
LOG_FILE="zfs_install_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"

# Function to log commands and their outputs
log_cmd() {
  echo "Running: $@" | tee -a "$LOG_FILE"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local status=${PIPESTATUS[0]}
  if [ $status -ne 0 ]; then
    echo "Command failed with status $status. Exiting." | tee -a "$LOG_FILE"
    exit $status
  fi
  return $status
}

# Function to check if the user wants to proceed after a command completes
check_proceed() {
  echo "Previous command completed. Continue? (y/n)" | tee -a "$LOG_FILE"
  read answer
  echo "User responded: $answer" >> "$LOG_FILE"
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Script canceled by user" | tee -a "$LOG_FILE"
    exit 1
  fi
}

echo "Starting ZFS installation script at $(date)" | tee -a "$LOG_FILE"
echo "Logging all output to $LOG_FILE" | tee -a "$LOG_FILE"
echo "This script will pause after each major step for confirmation." | tee -a "$LOG_FILE"

# Check and import key if not already done
if ! pacman-key --list-keys 3056513887B78AEB &>/dev/null; then
  log_cmd sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  log_cmd sudo pacman-key --lsign-key 3056513887B78AEB
  echo "Key import completed successfully." | tee -a "$LOG_FILE"
else
  echo "Key already imported." | tee -a "$LOG_FILE"
fi
check_proceed

# Install Chaotic AUR keyring and mirror list if not already done
if ! grep -q 'chaotic-aur' /etc/pacman.conf; then
  log_cmd sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
  log_cmd sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  echo '[chaotic-aur]' | sudo tee -a /etc/pacman.conf | tee -a "$LOG_FILE"
  echo 'Include = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf | tee -a "$LOG_FILE"
  echo "Chaotic AUR repository added successfully." | tee -a "$LOG_FILE"
else
  echo "Chaotic AUR repository already configured." | tee -a "$LOG_FILE"
fi
check_proceed

# Update the system
echo "Updating system packages..." | tee -a "$LOG_FILE"
log_cmd sudo pacman -Sy
echo "System update completed successfully." | tee -a "$LOG_FILE"
check_proceed

# Generate host ID
echo "Generating host ID..." | tee -a "$LOG_FILE"
log_cmd zgenhostid
echo "Host ID generated successfully: $(hostid)" | tee -a "$LOG_FILE"
check_proceed

# Define disk
echo "Enter target disk (e.g., /dev/disk/by-id/nvme0n1): " | tee -a "$LOG_FILE"
read DISK
echo "Selected disk: $DISK" | tee -a "$LOG_FILE"

# Verify the disk exists
if [ ! -e "$DISK" ]; then
  echo "Error: Disk $DISK does not exist!" | tee -a "$LOG_FILE"
  exit 1
fi

echo "WARNING: All data on $DISK will be destroyed!"
echo "Are you absolutely sure you want to continue? (type YES to confirm)" | tee -a "$LOG_FILE"
read confirmation
echo "User response: $confirmation" >> "$LOG_FILE"
if [ "$confirmation" != "YES" ]; then
  echo "Operation cancelled by user" | tee -a "$LOG_FILE"
  exit 1
fi

# Partition the disk
echo "Partitioning disk $DISK..." | tee -a "$LOG_FILE"
log_cmd sgdisk --zap-all "$DISK"
log_cmd sgdisk -n1:1M:+512M -t1:EF00 "$DISK"
log_cmd sgdisk -n2:0:0 -t2:BF00 "$DISK"
echo "Disk partitioning completed successfully." | tee -a "$LOG_FILE"
check_proceed

# Ensure disk partitions are detected
echo "Waiting for partition updates to be detected by the system..." | tee -a "$LOG_FILE"
sleep 3
if [ ! -e "${DISK}-part1" ] || [ ! -e "${DISK}-part2" ]; then
  echo "Error: Disk partitions not detected. Please check if ${DISK}-part1 and ${DISK}-part2 exist." | tee -a "$LOG_FILE"
  exit 1
fi

# Create ZFS pool
echo "Creating ZFS pool..." | tee -a "$LOG_FILE"
log_cmd zpool create -f -o ashift=12 \
 -O compression=zstd \
 -O acltype=posixacl \
 -O xattr=sa \
 -O relatime=on \
 -o autotrim=on \
 -m none zroot "${DISK}-part2"

# Verify pool creation
log_cmd zpool status zroot
echo "ZFS pool created successfully." | tee -a "$LOG_FILE"
check_proceed

# Create ZFS datasets
echo "Creating ZFS datasets..." | tee -a "$LOG_FILE"
log_cmd zfs create -o mountpoint=none zroot/ROOT
log_cmd zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/arch
log_cmd zfs create -o mountpoint=/Data zroot/Data
log_cmd zfs list
echo "ZFS datasets created successfully." | tee -a "$LOG_FILE"
check_proceed

# Export and re-import the pool
echo "Exporting and reimporting ZFS pool..." | tee -a "$LOG_FILE"
log_cmd zpool export zroot
log_cmd zpool import -N -R /mnt zroot
echo "ZFS pool exported and reimported successfully." | tee -a "$LOG_FILE"
check_proceed

# Mount the datasets
echo "Mounting ZFS datasets..." | tee -a "$LOG_FILE"
log_cmd zfs mount zroot/ROOT/arch
log_cmd zfs mount zroot/Data
log_cmd mount | grep zroot
echo "ZFS datasets mounted successfully." | tee -a "$LOG_FILE"
check_proceed

# Format and mount the EFI partition
echo "Formatting and mounting EFI partition..." | tee -a "$LOG_FILE"
log_cmd mkfs.vfat -F 32 -n EFI "${DISK}-part1"
log_cmd mkdir -p /mnt/efi
log_cmd mount "${DISK}-part1" /mnt/efi
log_cmd mount | grep efi
echo "EFI partition formatted and mounted successfully." | tee -a "$LOG_FILE"
check_proceed

# Install base system
echo "Installing base system packages (this may take a while)..." | tee -a "$LOG_FILE"
log_cmd pacstrap /mnt base linux-lts linux-firmware linux-lts-headers wget nano efibootmgr
echo "Base system packages installed successfully." | tee -a "$LOG_FILE"
check_proceed

# Install ZFS packages
echo "Installing ZFS packages..." | tee -a "$LOG_FILE"
log_cmd pacstrap /mnt zfs-dkms
echo "ZFS packages installed successfully." | tee -a "$LOG_FILE"
check_proceed

# Copy configuration files
echo "Copying configuration files..." | tee -a "$LOG_FILE"
log_cmd cp /etc/hostid /mnt/etc
log_cmd cp /etc/resolv.conf /mnt/etc
log_cmd mkdir -p /mnt/etc/zfs
log_cmd cp /etc/pacman.conf /mnt/etc/pacman.conf
echo "Configuration files copied successfully." | tee -a "$LOG_FILE"
check_proceed

# Generate fstab
echo "Generating fstab..." | tee -a "$LOG_FILE"
log_cmd genfstab /mnt > /mnt/etc/fstab
echo "Created fstab. Remember to keep only the line containing /efi." | tee -a "$LOG_FILE"

# Create a script to edit fstab
cat > /mnt/edit_fstab.sh << 'EOF'
#!/bin/bash
echo "Original fstab:"
cat /etc/fstab
echo ""
echo "Keeping only the EFI partition line..."
grep "/efi" /etc/fstab > /tmp/new_fstab
mv /tmp/new_fstab /etc/fstab
echo "New fstab:"
cat /etc/fstab
EOF
chmod +x /mnt/edit_fstab.sh
echo "Created edit_fstab.sh script" | tee -a "$LOG_FILE"
check_proceed

# Copy log file to the new system
log_cmd cp "$LOG_FILE" "/mnt/root/"
echo "Copied log file to /mnt/root/$LOG_FILE" | tee -a "$LOG_FILE"

# Create a script to run inside the chroot
cat > /mnt/chroot_setup.sh << EOF
#!/bin/bash

# Create log file in chroot
CHROOT_LOG="/root/chroot_setup_\$(date +%Y%m%d_%H%M%S).log"
touch "\$CHROOT_LOG"

# Function to log commands and their outputs
log_cmd() {
  echo "Running: \$@" | tee -a "\$CHROOT_LOG"
  "\$@" 2>&1 | tee -a "\$CHROOT_LOG"
  local status=\${PIPESTATUS[0]}
  if [ \$status -ne 0 ]; then
    echo "Command failed with status \$status. Exiting." | tee -a "\$CHROOT_LOG"
    exit \$status
  fi
  return \$status
}

# Function to check if the user wants to proceed after a command completes
check_proceed() {
  echo "Previous command completed. Continue? (y/n)" | tee -a "\$CHROOT_LOG"
  read answer
  echo "User responded: \$answer" >> "\$CHROOT_LOG"
  if [[ "\$answer" != "y" && "\$answer" != "Y" ]]; then
    echo "Script canceled by user" | tee -a "\$CHROOT_LOG"
    exit 1
  fi
}

echo "Starting chroot setup at \$(date)" | tee -a "\$CHROOT_LOG"
echo "This script will pause after each major step for confirmation." | tee -a "\$CHROOT_LOG"

# Edit fstab first
echo "First, let's edit the fstab to keep only the EFI line" | tee -a "\$CHROOT_LOG"
/edit_fstab.sh
check_proceed

# Set timezone
echo "Setting timezone..." | tee -a "\$CHROOT_LOG"
log_cmd ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
log_cmd hwclock --systohc
echo "Timezone set to Europe/London" | tee -a "\$CHROOT_LOG"
check_proceed

# Configure locale
echo "Configuring locale..." | tee -a "\$CHROOT_LOG"
log_cmd sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
log_cmd locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "Set locale to en_US.UTF-8" | tee -a "\$CHROOT_LOG"
check_proceed

# Set hostname
echo "Setting hostname..." | tee -a "\$CHROOT_LOG"
read -p "Enter hostname: " hostname
echo "\$hostname" > /etc/hostname
echo "127.0.0.1   localhost" > /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   \$hostname" >> /etc/hosts
echo "Set hostname to \$hostname" | tee -a "\$CHROOT_LOG"
check_proceed

# Configure initramfs
echo "Configuring initramfs..." | tee -a "\$CHROOT_LOG"
log_cmd sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
log_cmd mkinitcpio -P
echo "Initramfs configured successfully" | tee -a "\$CHROOT_LOG"
check_proceed

# Set root password
echo "Setting root password:" | tee -a "\$CHROOT_LOG"
until passwd; do
  echo "Password setting failed, try again" | tee -a "\$CHROOT_LOG"
done
echo "Root password set successfully" | tee -a "\$CHROOT_LOG"
check_proceed

# Configure ZFS boot
echo "Configuring ZFS boot services..." | tee -a "\$CHROOT_LOG"
log_cmd zpool set bootfs=zroot/ROOT/arch zroot
log_cmd systemctl enable zfs-import-cache
log_cmd systemctl enable zfs-import.target
log_cmd systemctl enable zfs-mount
log_cmd systemctl enable zfs-zed
log_cmd systemctl enable zfs.target
echo "ZFS boot services configured successfully" | tee -a "\$CHROOT_LOG"
check_proceed

# Set up ZFSBootMenu
echo "Setting up ZFSBootMenu..." | tee -a "\$CHROOT_LOG"
log_cmd mkdir -p /efi/EFI/zbm
log_cmd wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zbm/zfsbootmenu.EFI
echo "ZFSBootMenu setup completed" | tee -a "\$CHROOT_LOG"
check_proceed

# Create EFI boot entry
echo "Creating EFI boot entry..." | tee -a "\$CHROOT_LOG"
disk_base="\$(echo "$DISK" | sed 's/-part[0-9]*\$//')"
log_cmd efibootmgr --disk \$disk_base --part 1 --create --label "ZFSBootMenu" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose
echo "EFI boot entry created successfully" | tee -a "\$CHROOT_LOG"
check_proceed

# Set ZFS command line
echo "Setting ZFS command line..." | tee -a "\$CHROOT_LOG"
log_cmd zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
echo "ZFS command line set successfully" | tee -a "\$CHROOT_LOG"

echo "Chroot setup completed at \$(date)" | tee -a "\$CHROOT_LOG"
echo "Log saved to \$CHROOT_LOG"
echo ""
echo "ALL CONFIGURATION COMPLETED SUCCESSFULLY!"
echo "Exit the chroot by typing 'exit' and then continue with the main script."
EOF

chmod +x /mnt/chroot_setup.sh
echo "Created chroot_setup.sh script" | tee -a "$LOG_FILE"
check_proceed

# Chroot into the system
echo "Now you will be chrooted into the new system to complete the setup." | tee -a "$LOG_FILE"
echo "Run the script /chroot_setup.sh to continue the installation." | tee -a "$LOG_FILE"
echo "Entering chroot..." | tee -a "$LOG_FILE"
log_cmd arch-chroot /mnt
echo "Exited from chroot environment." | tee -a "$LOG_FILE"
check_proceed

# After exiting the chroot, unmount and reboot
echo "Unmounting filesystems and exporting ZFS pool..." | tee -a "$LOG_FILE"
log_cmd umount /mnt/efi
log_cmd zpool export zroot

echo "Installation complete! The system is ready to reboot." | tee -a "$LOG_FILE"
echo "Full installation log saved to $LOG_FILE and copied to the new system." | tee -a "$LOG_FILE"
echo ""
echo "Type 'reboot' to restart into your new ZFS system."
