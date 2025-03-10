#!/bin/bash

# Copy log file to the new system
cp "$LOG_FILE" "/mnt/root/"
echo "Copied log file to /mnt/root/$LOG_FILE"
confirm

# Create a script to run inside the chroot
cat > /mnt/chroot_setup.sh << EOF
#!/bin/bash

# Create log file in chroot
CHROOT_LOG="/root/chroot_setup_\$(date +%Y%m%d_%H%M%S).log"
touch "\$CHROOT_LOG"

# Function to log commands and their outputs
log_cmd() {
  echo "Running: \$@"
  "\$@"
  local status=\${PIPESTATUS[0]}
  if [ \$status -ne 0 ]; then
    echo "Command failed with status \$status. Exiting."
    exit \$status
  fi
  return \$status
}

echo "Starting chroot setup at \$(date)"

# Edit fstab first
echo "First, let's edit the fstab to keep only the EFI line"
/edit_fstab.sh
confirm

# Set timezone
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
echo "Timezone set to Europe/London"
confirm

# Configure locale
echo "Configuring locale..."
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "Set locale to en_US.UTF-8"
confirm

# Set hostname
hostname="archlinux"
echo "\$hostname" > /etc/hostname
echo "127.0.0.1   localhost" > /etc/hosts
echo "::1         localhost" >> /etc/hosts
echo "127.0.1.1   \$hostname" >> /etc/hosts
echo "Set hostname to \$hostname"
confirm

# Configure initramfs
echo "Configuring initramfs..."
sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P
echo "Initramfs configured successfully"
confirm

# Set root password
echo "Setting root password:"
echo "root:password" | chpasswd
echo "Root password set successfully"
confirm

# Configure ZFS boot
echo "Configuring ZFS boot services..."
zpool set bootfs=zroot/ROOT/arch zroot
systemctl enable zfs-import-cache
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs-zed
systemctl enable zfs.target
echo "ZFS boot services configured successfully"
confirm

# Set up ZFSBootMenu
echo "Setting up ZFSBootMenu..."
mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zfsbootmenu.EFI
echo "ZFSBootMenu setup completed"
confirm

# Verify ZFSBootMenu EFI file
echo "Verifying ZFSBootMenu EFI file..."
ls -l /efi/EFI/zbm/zfsbootmenu.EFI
confirm

# Create EFI boot entry
disk_base="\$(echo "$DISK" | sed 's/-part[0-9]*\$//')"
efibootmgr --disk \$disk_base --part 1 --create --label "ZFSBootMenu" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" --verbose
echo "EFI boot entry created successfully"
confirm

# Verify EFI boot entry
echo "Verifying EFI boot entry..."
efibootmgr
confirm

# Set ZFS command line
echo "Setting ZFS command line..."
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
echo "ZFS command line set successfully"
confirm

echo "Chroot setup completed at \$(date)"
echo "Log saved to \$CHROOT_LOG"
echo ""
echo "ALL CONFIGURATION COMPLETED SUCCESSFULLY!"
echo "Exit the chroot by typing 'exit' and then continue with the main script."
EOF

chmod +x /mnt/chroot_setup.sh
echo "Created chroot_setup.sh script"

# Chroot into the system
echo "Now you will be chrooted into the new system to complete the setup."
echo "Run the script /chroot_setup.sh to continue the installation."
arch-chroot /mnt

umount /mnt/efi
zpool export zroot
