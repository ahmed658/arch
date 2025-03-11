#!/bin/bash

# Copy log file to the new system
cp "$LOG_FILE" "/mnt/root/"
sleep 10

# Create a script to run inside the chroot
cat > /mnt/chroot_setup.sh << EOF
#!/bin/bash

# Edit fstab first
/edit_fstab.sh
sleep 10

# Set timezone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
sleep 10

# Configure locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
sleep 10

# Set hostname
hostname="SmallBrother"
echo "\$hostname" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 \$hostname" >> /etc/hosts
sleep 10

# Configure initramfs
sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
mkinitcpio -P
sleep 10

# Set root password
echo "root:AcerPowerF#1" | chpasswd
sleep 10

# Configure ZFS boot
zpool set bootfs=zroot/ROOT/arch zroot
systemctl enable zfs-import-cache
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs-zed
systemctl enable zfs.target
sleep 10

# Set up ZFSBootMenu
mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zfsbootmenu.EFI
sleep 10

# Create EFI boot entry
disk_base="\$(echo "$DISK" | sed 's/-part[0-9]*\$//')"
efibootmgr --disk \$disk_base --part 1 --create --label "ZFSBootMenu" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid"
sleep 10

# Set ZFS command line
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
sleep 10

echo "Chroot setup completed."
EOF

chmod +x /mnt/chroot_setup.sh
sleep 10

# Chroot into the system
arch-chroot /mnt
umount /mnt/efi
zpool export zroot
