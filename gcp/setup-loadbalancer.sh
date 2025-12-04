#!/bin/bash

# ============================================================
# Setup Nginx Load Balancer on GCP
# ============================================================
# Run this from Cloud Shell after the main setup.sh

set -e

ZONE="europe-west2-a"
NETWORK_NAME="whiteboard-network"
SUBNET_NAME="whiteboard-subnet"

# Get whiteboard node IPs
NODE1_IP=$(gcloud compute instances describe whiteboard-node-1 --zone=$ZONE --format='get(networkInterfaces[0].networkIP)')
NODE2_IP=$(gcloud compute instances describe whiteboard-node-2 --zone=europe-west2-b --format='get(networkInterfaces[0].networkIP)')

echo "Node 1 IP: $NODE1_IP"
echo "Node 2 IP: $NODE2_IP"

# Create Load Balancer VM
echo "Creating Load Balancer VM..."
gcloud compute instances create whiteboard-lb \
    --zone=$ZONE \
    --machine-type=e2-small \
    --network=$NETWORK_NAME \
    --subnet=$SUBNET_NAME \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --tags=http-server,https-server \
    --metadata=node1-ip=$NODE1_IP,node2-ip=$NODE2_IP \
    --metadata-from-file=startup-script=lb-startup.sh \
    2>/dev/null || echo "LB VM already exists"

echo ""
echo "Load Balancer VM created!"
echo "External IP:"
gcloud compute instances describe whiteboard-lb --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
