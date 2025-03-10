#!/bin/bash

# Generate host ID
echo "Generating host ID..."
zgenhostid
echo "Host ID generated successfully: $(hostid)"
confirm

# Verify host ID generation
echo "Verifying host ID generation..."
hostid
echo "Host ID verification completed."
confirm

# Define disk (you can specify the disk directly)
DISK="/dev/disk/by-id/nvme0n1"
echo "Selected disk: $DISK"
confirm

# Verify the disk exists
if [ ! -e "$DISK" ]; then
  echo "Error: Disk $DISK does not exist!"
  exit 1
fi
confirm

echo "WARNING: All data on $DISK will be destroyed!"
confirm

# Partition the disk
echo "Partitioning disk $DISK..."
sgdisk --zap-all "$DISK"
sgdisk -n1:1M:+512M -t1:EF00 "$DISK"
sgdisk -n2:0:0 -t2:BF00 "$DISK"
echo "Disk partitioning completed successfully."
confirm

# Display partition table
echo "Displaying partition table for $DISK..."
sgdisk -p "$DISK"
echo "Partition table display completed."
confirm

# Ensure disk partitions are detected
echo "Waiting for partition updates to be detected by the system..."
sleep 3
if [ ! -e "${DISK}-part1" ] || [ ! -e "${DISK}-part2}" ]; then
  echo "Error: Disk partitions not detected. Please check if ${DISK}-part1 and ${DISK}-part2 exist."
  exit 1
fi
confirm
