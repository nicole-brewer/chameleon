# Deploy a Jupyter Notebook Server with OpenStack and Blazar

## Introduction to Blazar
Blazar is OpenStack's Resource Reservation Service, designed to help you manage and reserve cloud resources efficiently.

### Why Blazar?
Blazar lets you automate resource reservation, which is especially valuable for repeated or shared project use. Unlike manually reserving resources through the OpenStack interface, Blazar allows you to easily set up recurring reservations and manage resources across multiple projects or users.

### Key Terms
**Reservation**: Allocation of cloud resources to a project. It includes details like status, resource type, identifier, and associated lease.

**Lease**: An agreement between Blazar (using OpenStack resources) and a user. It specifies the start and end times for the reserved resources, the set of reservations, and any events that might occur.

## Prerequisites

1. OpenStack and Blazar

You must have the OpenStack and Blazar clients installed in your environment. If you don't have them already, you can install the with conda.

```
# check if you have openstack and blazar
openstack --help
blazar --help

# if you need them you can install the with conda using...
conda env create -f environment.yaml
```

2. [Download the OpenRC Script](https://chameleoncloud.readthedocs.io/en/latest/technical/cli.html#cli-rc-script)
3. [Create ssh keypair](https://chameleoncloud.readthedocs.io/en/latest/technical/gui.html#creating-a-key-pair)
4. [Set up OpenStack CLI password](https://chameleoncloud.readthedocs.io/en/latest/technical/cli.html#setting-a-cli-password) 

## Run Available Scripts

Note that we `source` some of these scripts, which makes environment variables available from the command line should we need them.

`source create_jupyter_server.sh` - provision a server that is ready to run JupyterLab. Includes creating a lease, public IP, a security group that makes port 22 (ssh), 80 (http) and 8888 available

`source status_check.sh` - checks for existing resources and resets environment variables

`./teardown.sh` - may be used to teardown any reserved resources. Autogenerated by `create_jupyter_server.sh`

## Use

Run `create_jupyter_server.sh` to provision a server and run JupyterLab using OpenStack. If you have issues in the deployment stage, you have two options: 1) you can use the `status_check.sh` script to get the names and IDs of resources you created for the purposes of troubleshooting or 2) you can tear down any resources you did manage to create using `teardown.sh`, which is auto-generated while `create_jupyter_server.sh` is running. Access the JupyterLab instance using the provided IP and port 8888.
