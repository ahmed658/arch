#!/bin/bash

# Copy configuration files
echo "Copying configuration files..."
cp /etc/hostid /mnt/etc
sleep 10
cp /etc/resolv.conf /mnt/etc
sleep 10
mkdir -p /mnt/etc/zfs
sleep 10
cp /etc/pacman.conf /mnt/etc/pacman.conf
echo "Configuration files copied successfully."
sleep 10

# Generate fstab
echo "Generating fstab..."
genfstab /mnt > /mnt/etc/fstab
echo "Created fstab. Remember to keep only the line containing /efi."
sleep 10

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
echo "Created edit_fstab.sh script"
sleep 10
