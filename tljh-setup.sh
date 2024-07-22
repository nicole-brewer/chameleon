#!/bin/bash

echo "Start the littlest jupyter hub instance..."
PUBLIC_IP=$(curl -s ifconfig.me)
echo "You may check on the progress on the install by visiting $PUBLIC_IP in your browser"

# Download and run the TLJH bootstrap script with plugin installation
curl -L https://tljh.jupyter.org/bootstrap.py \
    | sudo python3 - \
    --admin admin \
    --show-progress-page 

# Check if the previous command was successful
if [ $? -ne 0 ]; then
  echo "Failed to run the TLJH bootstrap script."
  exit 1
fi

echo "TLJH bootstrap script ran successfully."

echo "Create self-signed certificate and add it to tljh config"
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/jupyterhub.key -out /etc/ssl/certs/jupyterhub.crt
sudo tljh-config set https.tls.key /etc/ssl/private/jupyterhub.key 
sudo tljh-config set https.tls.cert /etc/ssl/certs/jupyterhub.crt
sudo tljh-config add-item https.tls.domains $PUBLIC_IP
sudo tljh-config reload proxy
# allows the admin to login for the first time with any password they choose
sudo tljh-config set auth.type firstuseauthenticator.FirstUseAuthenticator
