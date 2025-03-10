#!/bin/bash

# Ensure the device wlan0 is powered on
iwctl device wlan0 set-property Powered on

# Scan for available networks
iwctl station wlan0 scan

# Wait for the scan to complete
sleep 5

# Connect to the network "Mosalam" with the password "10001000"
iwctl --passphrase 10001000 station wlan0 connect Mosalam

echo "Connected to the Wi-Fi network Mosalam"

# Clone your GitHub repository
git clone https://github.com/mahmoudmosalam/arch

# Change to the 'arch' directory
cd arch

# Make all files executable
chmod +x *.*

echo "GitHub repository cloned and all files made executable"
