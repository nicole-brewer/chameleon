#!/bin/bash

sudo apt-get update
# Loop through the list of packages
for pkg in python3-pip python3-dev; do
    if ! command -v "$pkg" &> /dev/null; then
        echo "$pkg is not installed. Installing $pkg..."
        sudo apt-get install -y "$pkg"
    fi
done

# Allow port 8888
echo "Allowing traffic on port 8888..."
sudo firewall-cmd --permanent --add-port=8888/tcp
sudo firewall-cmd --reload


