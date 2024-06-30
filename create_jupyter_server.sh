#!/bin/bash

export OS_REGION_NAME='CHI@UC'
export LEASE_NAME="$USER-test"
export SERVER_NAME="$USER-server"

export PRIVATE_NETWORK_NAME="sharednet1" # default/recommended network
export PUBLIC_NETWORK_NAME="public" # default/recommended network
export NODE_TYPE="compute_skylake" # a popular Intel CPU good for general applications
export NUM_SERVERS=2 # two servers??? 

echo "Creating lease..."
lease_status=""


# Delete old lease
#blazar lease-delete "$LEASE_NAME"

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

export SSHKEY_FILE="$HOME/work/.ssh/id_rsa"
export SSHKEY_NAME="chameleon-jupyter-interface"

echo "Requesting a floating IP..."
# Request a public floating IP (in the 'public' network)
server_ip=$(openstack floating ip create public --format value -c floating_ip_address)
echo "Public IP for this lab is $server_ip"

# add floating ip to teardown script
echo "openstack floating ip delete $server_ip" >> teardown.sh

echo "Creating security group..."
openstack security group create "${USER}-flinc-security-group" --description "Security group for SSH, HTTP, and Jupyter"

# Allow SSH (port 22)
openstack security group rule create --proto tcp --dst-port 22 --ingress "${USER}-flinc-security-group"

# Allow HTTP (port 80)
openstack security group rule create --proto tcp --dst-port 80 --ingress "${USER}-flinc-security-group"

# Allow Jupyter (port 8888)
openstack security group rule create --proto tcp --dst-port 8888 --ingress "${USER}-flinc-security-group"

# add line to teardown script
echo "openstack security group delete ${USER}-flinc-security-group"


echo "Creating baremetal servers..."
for i in left right
do
  openstack server create \
  --flavor "baremetal" \
  --image "CC-Ubuntu20.04" \
  --nic net-id="$network_id" \
  --hint reservation="$lease_id" \
  --key-name="$SSHKEY_NAME" \
  --security-group "${USER}-flinc-security-group"  \
  "$SERVER_NAME-$i"
done

# add line to teardown script
echo "openstack server delete $SERVER_NAME-left"
echo "openstack server delete $SERVER_NAME-right"

echo ""
echo "WARNING: this next step may take anywhere from 10-15 minutes"
echo ""


# Variables
#r-rightserver_name="nbrewer6_asu_edu-server-right"
expected_status="ACTIVE"
timeout_minutes=15
check_interval=60  # Check every 60 seconds
dot_interval=10  # Print a dot every 10 seconds

# Start waiting and checking loop
elapsed_time=0
while [ $elapsed_time -lt $((timeout_minutes * 60)) ]
do
    # Check the server status
    server_status=$(openstack server show "$server_name" | grep -w "status" | awk '{print $4}')
    echo "Current server status: $server_status"

    # Break the loop if the expected status is reached
    if [ "$server_status" == "$expected_status" ]; then
        echo "Server $server_name is now $expected_status."
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
    echo "Timeout reached. Server $server_name did not become $expected_status within $timeout_minutes minutes."
fi

echo "Server status is $server_status"


# Assign a public floating IP ONLY to $SERVER_NAME-left
openstack server add floating ip "$SERVER_NAME-left" "$server_ip"

# Check if we can connect to server on port 22.
ssh_status=""
echo -n "Checking connection to ${server_ip} on port 22..."

while [ "$ssh_status" != "Up" ]
do
    echo "Attempting to connect to ${server_ip} on port 22..."

    elapsed_time=0
    while [ $elapsed_time -lt 30 ]
    do
        sleep 5
        echo -n "."
        elapsed_time=$((elapsed_time + 5))
    done
    echo -n " "
    
    ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no "${server_ip}" exit &> /dev/null
    if [ $? -eq 0 ]; then
        ssh_status="Up"
    else
        ssh_status="Down"
    fi
    echo "Current SSH status: $ssh_status"
done

echo "${SERVER_NAME} (${server_ip}) is $ssh_status"

echo "TODO: Checking that we can run pwd on the LEFT server..."
ssh -i $SSHKEY_FILE -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes cc@$server_ip

login_command="ssh -o \"StrictHostKeyChecking no\" -i $SSHKEY_FILE cc@$server_ip"
eval "$login_command" pwd 


login_command="ssh -i $SSHKEY_FILE -o ConnectTimeout=10 cc@$server_ip"

# Execute command on left server and check if it succeeded
if eval "$login_command" pwd; then
    echo "SUCCESS: connected to the left server and executed command."
    echo "To log into the left server remotely, use"
    echo ""
    echo "$login_command"
    echo ""
    echo "To execute a command without logging in, use"
    echo ""
    echo "eval \"$login_command\" <login_command>"
else
    echo "FAIL: Unable to connect to the server or execute command."
fi

#server_ip_right=$(openstack server list --format value -c Networks --name "$SERVER_NAME-right"| cut -d = -f 2)

#eval "$login_command" /bin/bash << EOF
#nc -z "${server_ip_right}" 22 && echo "Up" || echo "Down"
#EOF

#echo "Checking that we can run pwd on the RIGHT server..."
#login_command_right="ssh -o \"StrictHostKeyChecking no\" -i SSHKEY_FILE cc@server_ip_right"
#eval "$login_command_right" pwd


# TODO: I wonder if I can run all this from my own command line using the openrc