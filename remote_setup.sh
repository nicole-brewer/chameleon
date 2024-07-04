#!/bin/bash

#git clone https://github.com/nicole-brewer/Flinc.git
#cd Flinc
#git fetch
#git checkout chameleon origin/chameleon
#./startup.sh

sudo apt-get update
# Loop through the list of packages
for pkg in ufw net-tools python3-pip python3-dev; do
    if ! command -v "$pkg" &> /dev/null; then
        echo "$pkg is not installed. Installing $pkg..."
        sudo apt-get install -y "$pkg"
    fi
done

if ! command -v jupyter &> /dev/null; then
    sudo pip3 install jupyter
fi

# Allow port 8888
echo "Allowing traffic on port 8888..."
sudo ufw allow 8888/tcp

# Enable ufw if it's not enabled
if ! sudo ufw status | grep -q "Status: active"; then
    echo "Enabling ufw..."
    sudo ufw enable
fi

# Start Jupyter Notebook using 0.0.0.0 to bind to all network interfaces
jupyter notebook --ServerApp.ip='0.0.0.0' --ServerApp.open_browser=False --ServerApp.port=8888

