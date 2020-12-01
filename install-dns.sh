#!/bin/bash
source functions.sh

echo "$( date ) Install Bind9 DNS script start"

# Step 1. Check OS type and version
echo "Checking system..."
do_check_os

# Step 2. Update the OS
echo "Updating operating system..."
do_os_update

# Step 3. Setup hostname
echo "Setup hostname..."
do_setup_hostname


    echo "Install bind9..."
    do_install_bind9 "$DISTRO"

    echo "Setup Firewall"
    do_setup_firewall "$DISTRO" "$1"

echo "$( date ) Install Bind9 DNS script end"