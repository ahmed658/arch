#!/bin/bash

# Install Chaotic AUR keyring and mirror list if not already done
if ! grep -q 'chaotic-aur' /etc/pacman.conf; then
  sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
  sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  echo '[chaotic-aur]' | sudo tee -a /etc/pacman.conf
  echo 'Include = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf
  echo "Chaotic AUR repository added successfully."
else
  echo "Chaotic AUR repository already configured."
fi
confirm

# Verify Chaotic AUR configuration
echo "Verifying Chaotic AUR configuration..."
grep 'chaotic-aur' /etc/pacman.conf
echo "Chaotic AUR configuration verification completed."
confirm

# Update the system
echo "Updating system packages..."
sudo pacman -Syu
echo "System update completed successfully."
confirm
