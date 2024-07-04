#!/bin/bash

echo "Soucing openrc.sh. You may be asked to authenticate..."
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


echo "#######################################################"
echo "#                                                     #"
echo "#                       LEASE                         #"
echo "#                                                     #"
echo "#######################################################"

echo "Getting lease status..."
lease_status=$(blazar lease-show --format value -c status "$LEASE_NAME")

if [[ $lease_status == "ACTIVE" || $lease_status == "PENDING" || $lease_status == "STARTING" || $lease_status == "UPDATING" ]]; then
    echo "Lease $LEASE_NAME already exists and is in a valid state: $lease_status"
else
    blazar lease-create --physical-reservation \
          min="$NUM_SERVERS",max=$((NUM_SERVERS + 1 )),resource_properties='["=", "$node_type", "'"$NODE_TYPE"'"]' "$LEASE_NAME"
    lease_status=$(blazar lease-show --format value -c status "$LEASE_NAME")
fi

echo "Waiting for lease to be ACTIVE" 
# Now wait for lease to be ready before going to the next step
while [[ $lease_status != "ACTIVE" ]]
do
   echo -n "."
   sleep 5
   lease_status=$(blazar lease-show --format value -c status "$LEASE_NAME")
done

LEASE_ID=$(blazar lease-show  --format value -c  reservations "$LEASE_NAME" |grep \"id\"| cut -d \" -f4)
export LEASE_ID="$LEASE_ID"

echo "The lease id is $LEASE_ID"

echo "Lease $LEASE_NAME is ready for business."
echo "Creating teardown.sh for deleting resources allocated in this script..."
echo "You may teardown reserved resources at any time using"
echo "     ./teardown.sh"
echo "blazar lease-delete $LEASE_NAME" > teardown.sh

# Define the description to search for (the current user)
description_to_search="$USER"

lease_info=$(blazar lease-show --format json "$LEASE_NAME")
# Extract and export the floating IP address from the lease info
export SERVER_IP=$(echo "$lease_info" | jq -r '.reservations | fromjson | select(.resource_type=="virtual:floatingip") | .resource_id')

if [ -n "$SERVER_IP" ]; then
    echo "Floating IP $SERVER_IP already associated with lease $LEASE_NAMEP"
else
    echo "No floating IP associated with lease $LEASE_NAME"
    echo "Checking for unassigned floating IPs created by $USER..."
    # List all floating IPs and their descriptions, then filter based on the description
    floating_ip=$(openstack floating ip list --format json -c "Floating IP Address" -c Description | \
    jq -r --arg desc "$description_to_search" '.[] | select(.Description == $desc) | .["Floating IP Address"]')
    
    # Check if an unassigned floating IP was found with the appropriate description
    if [ -n "$floating_ip" ]; then
        echo "Found floating IP $floating_ip"
        export SERVER_IP=$floating_ip
    else
        echo "No floating IP previously created by $description_to_search."
        echo "Creating a floating IP..."
        
        # Step 1: Create the floating IP and capture its ID and address
        floating_ip_info=$(openstack floating ip create public --format json)
        # Check if the command was successful
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create floating IP."
            exit 1
        fi
        floating_ip_id=$(echo "$floating_ip_info" | jq -r '.id')
        floating_ip_address=$(echo "$floating_ip_info" | jq -r '.floating_ip_address')

        # Step 2: Add a description to the floating IP
        openstack floating ip set --description "$USER" "$floating_ip_id"

        # Export the floating IP address as SERVER_IP
        export SERVER_IP="$floating_ip_address"

        echo "Created and set new floating IP $SERVER_IP"
    fi 

    # whether floating ip was found or created, add floating ip to teardown script
    echo "openstack floating ip delete $SERVER_IP" >> teardown.sh
fi


# Develooper note: Remove lines starting with the server IP from .ssh/known_hosts
# so that if the IP is the same as a previous deployment, we don't
# get a security warning about known hosts
echo "Removing $SERVER_IP from list of known hosts"
sed -i.bak "/^$SERVER_IP/d" "$HOME/.ssh/known_hosts"
if [ $? -ne 0 ]; then 
    echo "[Warning] removal of known hosts associated with $SERVER_IP failed. This may result in a warning about a man in the middle attack in later steps, which can be ignored"
else
    echo "Successfully removed $SERVER_IP from $HOME/.ssh/known_hosts"
fi

echo "Getting the network ID associated with sharednet1..."
export NETWORK_ID=$(openstack network show --format value -c id $PRIVATE_NETWORK_NAME)
echo "The network id is $NETWORK_ID"

echo "#######################################################"
echo "#                                                     #"
echo "#                  SECURITY GROUP                     #"
echo "#                                                     #"
echo "#######################################################"

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
    echo "Security group with access to ports 22, 80, and 8888 already exists: $SECURITY_GROUP"
fi

echo "#######################################################"
echo "#                                                     #"
echo "#                      SERVER                         #"
echo "#                                                     #"
echo "#######################################################"

server_info=$(openstack server list --name "$SERVER_NAME" --format json)
server_name=$(echo "$server_info" | jq -r '.[0].Name')

if [ -n "$server_info" ] && [ "$server_name" == "$SERVER_NAME" ]; then
    server_status=$(echo "$server_info" | jq -r '.[0].Status')
    if [[ "$server_status" == "ACTIVE" || "$server_status" == "BUILD" ]]; then
        echo "Server $server_name associated with lease $LEASE_NAME exists and is in a usable state: $server_status."
    else
        echo "Server $server_name associated with lease $LEASE_NAME exists but is not in a usable state: $server_status."
        echo "Deleting server (2 minute wait)..."
        openstack server delete $SERVER_NAME
        wait 120
        echo "Creating new server..."
        openstack server create \
          --flavor "baremetal" \
          --image "CC-Ubuntu20.04" \
          --nic net-id="$NETWORK_ID" \
          --hint reservation="$LEASE_ID" \
          --key-name="$SSHKEY_NAME" \
          --security-group "$SECURITY_GROUP"  \
          "$SERVER_NAME"
    
        echo "#########################################################"
        echo "#                                                       #"
        echo "#                BUILDING SERVER                        #"
        echo "#                                                       #"
        echo "#.    Warning: this could take from 10 - 15 minutes     #"
        echo "#                                                       #"
        echo "#########################################################"
fi
else
    echo "No server associated with lease $LEASE_NAME."
    echo "Creating server...."
    openstack server create \
      --flavor "baremetal" \
      --image "CC-Ubuntu20.04" \
      --nic net-id="$NETWORK_ID" \
      --hint reservation="$LEASE_ID" \
      --key-name="$SSHKEY_NAME" \
      --security-group "$SECURITY_GROUP"  \
      "$SERVER_NAME"

    echo "#########################################################"
    echo "#                                                       #"
    echo "#                BUILDING SERVER                        #"
    echo "#                                                       #"
    echo "#.    Warning: this could take from 10 - 15 minutes     #"
    echo "#                                                       #"
    echo "#########################################################"
fi

# add line to teardown script
echo "openstack server delete $SERVER_NAME" >> teardown.sh


# Variables
timeout_minutes=20
check_interval=60  # Check every 60 seconds
dot_interval=10  # Print a dot every 10 seconds
description_to_search="$USER"

# Start waiting and checking loop
elapsed_time=0
while [ $elapsed_time -lt $((timeout_minutes * 60)) ]
do
    # Check the server status
    server_status=$(openstack server show "$SERVER_NAME" | grep -w "status" | awk '{print $4}')
    echo "Current server status: $server_status"

    # Break the loop if the expected status is reached
    if [ "$server_status" == "ACTIVE" ]; then
        echo "Server $SERVER_NAME is now ACTIVE."
        break
    fi

    # Print dots to indicate waiting
    echo -n "Waiting for server to become ACTIVE: "
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
if [ "$server_status" != "ACTIVE" ]; then
    echo "Timeout reached. Server $SERVER_NAME did not become ACTIVE within $timeout_minutes minutes."
    exit 1
fi

echo "#######################################################"
echo "#                                                     #"
echo "#                    FLOATING IP                      #"
echo "#                                                     #"
echo "#######################################################"

# Check if there is a floating IP attached to the server
attached_ip=$(openstack server show "$SERVER_NAME" --format json | jq -r '.addresses | to_entries[] | .value[] | select(.OS-EXT-IPS:type == "floating") | .addr')

if [ -n "$attached_ip" ]; then
    echo "Floating IP $attached_ip is already attached to server $SERVER_NAME."
    export SERVER_IP=$attached_ip
else
    echo "No floating IP attached to server $SERVER_NAME"
    echo "Creating floating IP..."

    # Create a new floating IP and capture its address
    floating_ip_address=$(openstack floating ip create public --format value -c floating_ip_address)

    # Attach the new floating IP to the server
    openstack server add floating ip "$SERVER_NAME" "$floating_ip_address"
    export SERVER_IP=$floating_ip_address

    echo "Created and attached new floating IP: $SERVER_IP to server $SERVER_NAME."

fi

echo "#######################################################"
echo "#                                                     #"
echo "#                   SSH CONNECTION                    #"
echo "#                                                     #"
echo "#######################################################"

# Check if we can connect to server on port 22.
ssh_status=""
echo "WARNING: the next step may take several minutes"
echo -n "Checking connection to $SERVER_IP on port 22..."

# Define the SSH command

export LOGIN_COMMAND="ssh -i $SSHKEY_FILE -o ConnectTimeout=10 cc@$SERVER_IP"

# Define the timeout and interval
timeout=900  # 15 minutes in seconds
interval=15  # 15 seconds
elapsed=0

while [ $elapsed -lt $timeout ]; do
    # Execute command on server and check if it succeeded
    REMOTE_HOME=$(eval "$LOGIN_COMMAND" pwd)
    if [ $? -eq 0 ]; then
        echo "SUCCESS: connected to the server and executed command."
        echo "To log into the server remotely, use"
        echo ""
        echo "eval \$LOGIN_COMMAND"
        echo ""
        echo "To execute a command without logging in, use"
        echo ""
        echo "eval \"$LOGIN_COMMAND\" <LOGIN_COMMAND>"
        break
    else
        echo -n "."  # Print a dot without a newline
    fi

    # Wait for the specified interval
    sleep $interval

    # Increment the elapsed time
    elapsed=$((elapsed + interval))
done

if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Connection timed out after $timeout seconds."
fi

echo "The remote directory is $REMOTE_HOME"
echo "Transfering remote_setup.sh to remote home directory..."
scp remote_setup.sh cc@$SERVER_IP:$REMOTE_HOME
eval $LOGIN_COMMAND sudo chmod 755 remote_setup.sh
eval $LOGIN_COMMAND ./remote_setup.sh
