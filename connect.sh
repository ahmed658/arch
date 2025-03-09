#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Start the interactive iwd command line interface
echo "Starting iwctl..."
iwctl <<EOF
# Scan for available Wi-Fi networks
station wlan0 scan

# Connect to the Wi-Fi network "Mosalam"
station wlan0 connect Mosalam

# Exit iwctl
exit
EOF

# Configure the network with the password
echo "Configuring network with password..."
cat <<EOT > /etc/iwd/Mosalam.psk
[Security]
PreSharedKey=10001000
EOT

# Restart iwd service
echo "Restarting iwd service..."
systemctl restart iwd

echo "Success: Connected to Wi-Fi network 'Mosalam'."
