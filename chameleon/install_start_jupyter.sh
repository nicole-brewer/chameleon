#!/bin/bash

if ! command -v jupyter &> /dev/null; then
    pip3 install jupyter notebook
fi

# Path to the .bashrc file
bashrc_path="$HOME/.bashrc"

# Line to be added
line_to_add='export PATH="$HOME/.local/bin:${PATH}"'

# Check if the line already exists in the .bashrc file
if ! grep -Fxq "$line_to_add" "$bashrc_path"; then
    # If the line doesn't exist, append it to the .bashrc file
    echo "$line_to_add" >> "$bashrc_path"
    echo "Added PATH line to $bashrc_path"
else
    echo "PATH line already exists in $bashrc_path"
fi

# Source the .bashrc to apply changes immediately
source "$bashrc_path"

# Start Jupyter Notebook using 0.0.0.0 to bind to all network interfaces
jupyter notebook --ServerApp.ip='0.0.0.0' --ServerApp.open_browser=False --ServerApp.port=8888
sudo firewall-cmd --permanent --add-port=8888/tcp
sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
