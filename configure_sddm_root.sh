#!/bin/bash

# Create the SDDM configuration directory if it doesn't exist
sudo mkdir -p /etc/sddm.conf.d

# Create and write the custom configuration file
sudo bash -c 'cat <<EOL > /etc/sddm.conf.d/root_login.conf
[Autologin]
Relogin=false

[Users]
DefaultPath=/usr/local/sbin:/usr/local/bin:/usr/bin
AllowRoot=true
EOL'

# Restart the SDDM service
sudo systemctl restart sddm

echo "SDDM configured to allow root login. Please try logging in as root in the graphical environment."
