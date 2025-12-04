#!/bin/bash

# ============================================================
# Setup Monitoring with Prometheus & Grafana on GCP
# ============================================================
# This creates monitoring for your private cloud

set -e

ZONE="europe-west2-a"
NETWORK_NAME="whiteboard-network"
SUBNET_NAME="whiteboard-subnet"

# Get all node IPs
REDIS_IP=$(gcloud compute instances describe redis-server --zone=$ZONE --format='get(networkInterfaces[0].networkIP)')
NODE1_IP=$(gcloud compute instances describe whiteboard-node-1 --zone=$ZONE --format='get(networkInterfaces[0].networkIP)')
NODE2_IP=$(gcloud compute instances describe whiteboard-node-2 --zone=europe-west2-b --format='get(networkInterfaces[0].networkIP)')

echo "Setting up monitoring VM..."

# Create monitoring VM
gcloud compute instances create monitoring \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --network=$NETWORK_NAME \
    --subnet=$SUBNET_NAME \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --tags=monitoring \
    --metadata=redis-ip=$REDIS_IP,node1-ip=$NODE1_IP,node2-ip=$NODE2_IP \
    2>/dev/null || echo "Monitoring VM already exists"

# Allow Grafana port
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-grafana \
    --network=$NETWORK_NAME \
    --allow=tcp:3001,tcp:9090 \
    --source-ranges=0.0.0.0/0 \
    2>/dev/null || echo "Grafana firewall rule already exists"

echo ""
echo "Monitoring VM created!"
echo "SSH in and run the monitoring setup:"
echo "gcloud compute ssh monitoring --zone=$ZONE"
