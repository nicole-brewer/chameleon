#!/bin/bash

if ! command -v jupyter &> /dev/null; then
    sudo pip3 install jupyter
fi

# Start Jupyter Notebook using 0.0.0.0 to bind to all network interfaces
jupyter notebook --ServerApp.ip='0.0.0.0' --ServerApp.open_browser=False --ServerApp.port=8888
