#!/bin/bash

# Create ZFS pool
echo "Creating ZFS pool..."
zpool create -f -o ashift=12 \
 -O compression=zstd \
 -O acltype=posixacl \
 -O xattr=sa \
 -O relatime=on \
 -o autotrim=on \
 -m none zroot "${DISK}-part2"
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
