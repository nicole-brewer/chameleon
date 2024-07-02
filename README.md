# Deploy Jupyter Notebook Server with OpenStack

## Prerequisites

1. Download openrc.sh
2. Create ssh keypair
3. Set up OpenStack authentication method

## Use

Run `create_jupyter_server.sh` to provision a server and run JupyterLab using OpenStack. If you have issues in the deployment stage, you have two options: 1) you can use the `status_check.sh` script to get the names and IDs of resources you created for the purposes of troubleshooting or 2) you can tear down any resources you did manage to create using `teardown.sh`, which is auto-generated while `create_jupyter_server.sh` is running. Access the JupyterLab instance using the provided IP and port 8888.