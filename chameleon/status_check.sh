#!/bin/bash

source openrc.sh

export PRIVATE_NETWORK_NAME="sharednet1" # default/recommended network
export PUBLIC_NETWORK_NAME="public" # default/recommended network
export NODE_TYPE="compute_skylake" # a popular Intel CPU good for general applications
export NUM_SERVERS=2 # two servers??? 
export OS_REGION_NAME='CHI@UC'
export LEASE_NAME="$USER-test"
export SERVER_NAME="$USER-server"

# Set default values
export SSHKEY_FILE='$HOME/.ssh/chameleon-jupyter-interface'
#"$HOME/work/.ssh/id_rsa"

lease_status=$(blazar lease-show --format value -c status "$LEASE_NAME")

export LEASE_ID=$(blazar lease-show  --format value -c  reservations "$LEASE_NAME" |grep \"id\"| cut -d \" -f4)

export NETWORK_ID=$(openstack network show --format value -c id $PRIVATE_NETWORK_NAME)

server_status=$(openstack server show "$SERVER_NAME" | grep -w "status" | awk '{print $4}')
echo "$SERVER_NAME, has status: $server_status"

export SERVER_IP=$(openstack server show "$SERVER_NAME" -f json | jq -r '.addresses.sharednet1[] | select(test("^\\d{3}"))')
echo "The fixed IP associated with $SERVER_NAME is $SERVER_IP"

export LOGIN_COMMAND="ssh -i $SSHKEY_FILE -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null cc@$SERVER_IP"
echo "Log into the node with $LOGIN_COMMAND"
echo "Run a command with"
echo "     eval \$LOGIN_COMMAND <cmd>"
echo "Login with with"
echo "     eval \$LOGIN_COMMAND"

export REMOTE_HOME=$(eval "$LOGIN_COMMAND" pwd)
echo "Add file to remote intstance with"
echo "     scp -i \$SSHKEY_FILE remote_setup.sh cc@\$SERVER_IP:\$REMOTE_HOME"
