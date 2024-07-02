#!/bin/bash

source openrc.sh

# Set default values
default_sshkey_file='$HOME/.ssh/chameleon-jupyter-interface'
#"$HOME/work/.ssh/id_rsa"

# Prompt the user for input with default values
read -p "Enter the SSH key file path [default: $default_sshkey_file]: " user_sshkey_file

# Use the user input if provided, otherwise use the default values
export SSHKEY_FILE="${user_sshkey_file:-$default_sshkey_file}"
export SSHKEY_NAME="chameleon-jupyter-interface"

export LEASE_NAME="$USER-test"
export SERVER_NAME="$USER-server"
export SECURITY_GROUP="${USER}-security-group"

export PRIVATE_NETWORK_NAME="sharednet1" # default/recommended network
export PUBLIC_NETWORK_NAME="public" # default/recommended network
export NODE_TYPE="compute_skylake" # a popular Intel CPU good for general applications
export NUM_SERVERS=1

echo "Creating lease..."
lease_status=""


blazar lease-create --physical-reservation \
      min="$NUM_SERVERS",max=$((NUM_SERVERS + 1 )),resource_properties='["=", "$node_type", "'"$NODE_TYPE"'"]' "$LEASE_NAME"
lease_status=$(blazar lease-show --format value -c status "$LEASE_NAME")

echo "Lease status: $lease_status"

# Now wait for lease to be ready before going to the next step
while [[ $lease_status != "ACTIVE" ]]
do
   sleep 5
   lease_status=$(blazar lease-show --format value -c status "$LEASE_NAME")
done

echo "Lease $LEASE_NAME is ready for business."
echo "Creating teardown.sh for deleting resources allocated in this script..."
echo "You may teardown reserved resources at any time using ./teardown.sh" 
echo "blazar lease-delete $LEASE_NAME" > teardown.sh
   
echo "Getting lease id..."
lease_id=$(blazar lease-show  --format value -c  reservations "$LEASE_NAME" |grep \"id\"| cut -d \" -f4)
echo "The lease id is $lease_id"


echo "Getting the network ID associated with sharednet1..."
network_id=$(openstack network show --format value -c id $PRIVATE_NETWORK_NAME)
echo "The network id is $network_id"

echo "Requesting a floating IP..."
# Request a public floating IP (in the 'public' network)
export SERVER_IP=$(openstack floating ip create public --format value -c floating_ip_address)

# Check if the command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to create floating IP."
    exit 1
fi

echo "Public IP for this lab is $SERVER_IP"

# add floating ip to teardown script
echo "openstack floating ip delete $SERVER_IP" >> teardown.sh

echo "Creating security group..."

# Check if the security group already exists
existing_sg=$(openstack security group list --format value -c Name | grep -w "$SECURITY_GROUP")

if [ -z "$existing_sg" ]; then
    # Security group does not exist, create it
    openstack security group create $SECURITY_GROUP

    # Check if the command was successful
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create security group."
        exit 1
    fi

    echo "Security group created: $SECURITY_GROUP"

    # Allow SSH (port 22)
    openstack security group rule create --proto tcp --dst-port 22 --ingress "$SECURITY_GROUP"
    
    # Allow HTTP (port 80)
    openstack security group rule create --proto tcp --dst-port 80 --ingress "$SECURITY_GROUP"
    
    # Allow Jupyter (port 8888)
    openstack security group rule create --proto tcp --dst-port 8888 --ingress "$SECURITY_GROUP"
else
    # Security group already exists
    echo "Security group already exists: $SECURITY_GROUP"
fi

# add line to teardown script
echo "openstack security group delete $SECURITY_GROUP" >> teardown.sh

openstack server create \
  --flavor "baremetal" \
  --image "CC-Ubuntu20.04" \
  --nic net-id="$network_id" \
  --hint reservation="$lease_id" \
  --key-name="$SSHKEY_NAME" \
  --security-group "$SECURITY_GROUP"  \
  "$SERVER_NAME"

# add line to teardown script
echo "openstack server delete $SERVER_NAME" >> teardown.sh

echo "|-----------------------------|"
echo "All resources provisioned:"
echo "Lease name: $LEASE_NAME"
echo "Server name: $SERVER_NAME"
echo "Security group: $SECURITY_GROUP"
echo "Public IP: $SERVER_IP"
echo "SSH key: $SSHKEY_NAME"
echo "|-----------------------------|"



echo ""
echo "WARNING: this next step may take anywhere from 10-15 minutes"
echo ""


# Variables
expected_status="ACTIVE"
timeout_minutes=20
check_interval=60  # Check every 60 seconds
dot_interval=10  # Print a dot every 10 seconds

# Start waiting and checking loop
elapsed_time=0
while [ $elapsed_time -lt $((timeout_minutes * 60)) ]
do
    # Check the server status
    server_status=$(openstack server show "$SERVER_NAME" | grep -w "status" | awk '{print $4}')
    echo "Current server status: $server_status"

    # Break the loop if the expected status is reached
    if [ "$server_status" == "$expected_status" ]; then
        echo "Server $SERVER_NAME is now $expected_status."
        break
    fi

    # Print dots to indicate waiting
    echo -n "Waiting for server to become $expected_status: "
    for ((i=0; i<$check_interval; i+=$dot_interval))
    do
        sleep $dot_interval
        echo -n "."
    done
    echo ""

    # Update elapsed time
    elapsed_time=$((elapsed_time + check_interval))
done

# Final check and message
if [ "$server_status" != "$expected_status" ]; then
    echo "Timeout reached. Server $SERVER_NAME did not become $expected_status within $timeout_minutes minutes."
fi

echo "Server status is $server_status"

# Assign a public floating IP ONLY to $SERVER_NAME
openstack server add floating ip "$SERVER_NAME" "$SERVER_IP"

# Check if we can connect to server on port 22.
ssh_status=""
echo -n "Checking connection to $SERVER_IP on port 22..."

# Define the SSH command
login_command="ssh -i $SSHKEY_FILE -o ConnectTimeout=10 cc@$SERVER_IP"

# Define the timeout and interval
timeout=900  # 15 minutes in seconds
interval=15  # 15 seconds
elapsed=0

while [ $elapsed -lt $timeout ]; do
    # Execute command on server and check if it succeeded
    if eval "$login_command" pwd; then
        echo "SUCCESS: connected to the server and executed command."
        echo "To log into the server remotely, use"
        echo ""
        echo "$login_command"
        echo ""
        echo "To execute a command without logging in, use"
        echo ""
        echo "eval \"$login_command\" <login_command>"
        exit 0
    else
        echo -n "."  # Print a dot without a newline
    fi

    # Wait for the specified interval
    sleep $interval

    # Increment the elapsed time
    elapsed=$((elapsed + interval))
done

echo "Connection to server failed."
exit 1
