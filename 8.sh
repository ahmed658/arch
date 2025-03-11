#!/bin/bash

# Copy log file to the new system
cp "$LOG_FILE" "/mnt/root/"

# Create a script to run inside the chroot
cat > /mnt/chroot_setup.sh << EOF
#!/bin/bash

# Edit fstab first
/edit_fstab.sh

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
sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
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

# Set up ZFSBootMenu
mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zfsbootmenu.EFI

# Create EFI boot entry
disk_base="\$(echo "$DISK" | sed 's/-part[0-9]*\$//')"
efibootmgr --disk \$disk_base --part 1 --create --label "ZFSBootMenu" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid"

# Set ZFS command line
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
EOF

chmod +x /mnt/chroot_setup.sh

# Chroot into the system
arch-chroot /mnt
umount /mnt/efi
zpool export zroot
#!/bin/bash

# Copy log file to the new system
cp "$LOG_FILE" "/mnt/root/"

# Create a script to run inside the chroot
cat > /mnt/chroot_setup.sh << EOF
#!/bin/bash

# Edit fstab first
/edit_fstab.sh

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
sed -i 's/HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)/' /etc/mkinitcpio.conf
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

# Set up ZFSBootMenu
mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zfsbootmenu.EFI

# Create EFI boot entry
disk_base="\$(echo "$DISK" | sed 's/-part[0-9]*\$//')"
efibootmgr --disk \$disk_base --part 1 --create --label "ZFSBootMenu" --loader '\\EFI\\zbm\\zfsbootmenu.EFI' --unicode "spl_hostid=\$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid"

# Set ZFS command line
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=\$(hostid)" zroot/ROOT
EOF

chmod +x /mnt/chroot_setup.sh

# Chroot into the system
arch-chroot /mnt
umount /mnt/efi
zpool export zroot
