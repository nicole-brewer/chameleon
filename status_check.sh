#!/bin/bash

source CHI-231217-openrc.sh

export OS_REGION_NAME='CHI@UC'
export LEASE_NAME="$USER-test"
export SERVER_NAME="$USER-server"

export PRIVATE_NETWORK_NAME="sharednet1" # default/recommended network
export PUBLIC_NETWORK_NAME="public" # default/recommended network
export NODE_TYPE="compute_skylake" # a popular Intel CPU good for general applications
export NUM_SERVERS=2 # two servers??? 

lease_status=$(blazar lease-show --format value -c status "$LEASE_NAME")
echo "Lease status: $lease_status"

export lease_id=$(blazar lease-show  --format value -c  reservations "$LEASE_NAME" |grep \"id\"| cut -d \" -f4)
echo "The lease id is $lease_id"

export network_id=$(openstack network show --format value -c id $PRIVATE_NETWORK_NAME)

echo "The network id is $network_id"

left_server_status=$(openstack server show "$SERVER_NAME-left" | grep -w "status" | awk '{print $4}')
echo "Left server, $SERVER_NAME-left, has status: $left_server_status"

right_server_status=$(openstack server show "$SERVER_NAME-right" | grep -w "status" | awk '{print $4}')
echo "Right server, $SERVER_NAME-left, has status: $right_server_status"

fixed_ip=$(openstack server show "$SERVER_NAME-left" -f json | jq -r '.addresses.sharednet1[] | select(test("^\\d{3}"))')
echo "The fixed IP associated with $SERVER_NAME-left is $fixed_ip"