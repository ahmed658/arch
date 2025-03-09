

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
