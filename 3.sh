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
sgdisk -n1:1M:+2G -t1:EF00 "$DISK"
sgdisk -n2:0:+100G -t2:BF00 "$DISK"
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
