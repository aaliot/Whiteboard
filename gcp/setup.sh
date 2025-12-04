#!/bin/bash

# ============================================================
# GCP Private Cloud Setup for Whiteboard Application
# ============================================================
# This script sets up the infrastructure on Google Cloud Platform
# Run this from Google Cloud Shell or a machine with gcloud CLI installed

set -e

# Configuration - MODIFY THESE VALUES
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
REGION="europe-west2"
ZONE="${REGION}-a"
NETWORK_NAME="whiteboard-network"
SUBNET_NAME="whiteboard-subnet"

# VM Configuration
MACHINE_TYPE="e2-medium"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

echo "============================================"
echo "Setting up GCP Private Cloud for Whiteboard"
echo "============================================"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Set the project
gcloud config set project $PROJECT_ID

# Enable required APIs
echo "[1/8] Enabling required GCP APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com

# Create VPC Network
echo "[2/8] Creating VPC Network..."
gcloud compute networks create $NETWORK_NAME \
    --subnet-mode=custom \
    --bgp-routing-mode=regional \
    2>/dev/null || echo "Network already exists"

# Create Subnet
echo "[3/8] Creating Subnet..."
gcloud compute networks subnets create $SUBNET_NAME \
    --network=$NETWORK_NAME \
    --region=$REGION \
    --range=10.0.0.0/24 \
    2>/dev/null || echo "Subnet already exists"

# Create Firewall Rules
echo "[4/8] Creating Firewall Rules..."

# Allow internal communication
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-internal \
    --network=$NETWORK_NAME \
    --allow=tcp,udp,icmp \
    --source-ranges=10.0.0.0/24 \
    2>/dev/null || echo "Internal firewall rule already exists"

# Allow SSH
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-ssh \
    --network=$NETWORK_NAME \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    2>/dev/null || echo "SSH firewall rule already exists"

# Allow HTTP/HTTPS and app ports
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-web \
    --network=$NETWORK_NAME \
    --allow=tcp:80,tcp:443,tcp:3000,tcp:8080,tcp:6379 \
    --source-ranges=0.0.0.0/0 \
    2>/dev/null || echo "Web firewall rule already exists"

# Allow health checks from GCP load balancer
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-health-check \
    --network=$NETWORK_NAME \
    --allow=tcp \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    2>/dev/null || echo "Health check firewall rule already exists"

# Create Redis VM (shared state)
echo "[5/8] Creating Redis VM..."
gcloud compute instances create redis-server \
    --zone=$ZONE \
    --machine-type=$MACHINE_TYPE \
    --network=$NETWORK_NAME \
    --subnet=$SUBNET_NAME \
    --image-family=$IMAGE_FAMILY \
    --image-project=$IMAGE_PROJECT \
    --tags=redis-server \
    --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y docker.io
systemctl start docker
systemctl enable docker
docker run -d --name redis --restart always -p 6379:6379 redis:7-alpine
' \
    2>/dev/null || echo "Redis VM already exists"

# Get Redis internal IP
REDIS_IP=$(gcloud compute instances describe redis-server --zone=$ZONE --format='get(networkInterfaces[0].networkIP)')
echo "Redis IP: $REDIS_IP"

# Create Whiteboard VM 1
echo "[6/8] Creating Whiteboard VM 1..."
gcloud compute instances create whiteboard-node-1 \
    --zone=$ZONE \
    --machine-type=$MACHINE_TYPE \
    --network=$NETWORK_NAME \
    --subnet=$SUBNET_NAME \
    --image-family=$IMAGE_FAMILY \
    --image-project=$IMAGE_PROJECT \
    --tags=whiteboard-server,http-server \
    --metadata=redis-ip=$REDIS_IP \
    --metadata-from-file=startup-script=vm-startup.sh \
    2>/dev/null || echo "Whiteboard VM 1 already exists"

# Create Whiteboard VM 2
echo "[7/8] Creating Whiteboard VM 2..."
gcloud compute instances create whiteboard-node-2 \
    --zone=${REGION}-b \
    --machine-type=$MACHINE_TYPE \
    --network=$NETWORK_NAME \
    --subnet=$SUBNET_NAME \
    --image-family=$IMAGE_FAMILY \
    --image-project=$IMAGE_PROJECT \
    --tags=whiteboard-server,http-server \
    --metadata=redis-ip=$REDIS_IP \
    --metadata-from-file=startup-script=vm-startup.sh \
    2>/dev/null || echo "Whiteboard VM 2 already exists"

# Create Instance Group for Load Balancing
echo "[8/8] Setting up Load Balancer..."

# Create unmanaged instance group
gcloud compute instance-groups unmanaged create whiteboard-group \
    --zone=$ZONE \
    2>/dev/null || echo "Instance group already exists"

gcloud compute instance-groups unmanaged add-instances whiteboard-group \
    --zone=$ZONE \
    --instances=whiteboard-node-1 \
    2>/dev/null || echo "Instance already in group"

# Create health check
gcloud compute health-checks create http whiteboard-health-check \
    --port=3000 \
    --request-path="/" \
    2>/dev/null || echo "Health check already exists"

# Create backend service
gcloud compute backend-services create whiteboard-backend \
    --protocol=HTTP \
    --health-checks=whiteboard-health-check \
    --global \
    2>/dev/null || echo "Backend service already exists"

gcloud compute backend-services add-backend whiteboard-backend \
    --instance-group=whiteboard-group \
    --instance-group-zone=$ZONE \
    --global \
    2>/dev/null || echo "Backend already added"

# Create URL map
gcloud compute url-maps create whiteboard-lb \
    --default-service=whiteboard-backend \
    2>/dev/null || echo "URL map already exists"

# Create HTTP proxy
gcloud compute target-http-proxies create whiteboard-http-proxy \
    --url-map=whiteboard-lb \
    2>/dev/null || echo "HTTP proxy already exists"

# Create forwarding rule (external IP)
gcloud compute forwarding-rules create whiteboard-forwarding-rule \
    --global \
    --target-http-proxy=whiteboard-http-proxy \
    --ports=80 \
    2>/dev/null || echo "Forwarding rule already exists"

echo ""
echo "============================================"
echo "Setup Complete!"
echo "============================================"
echo ""

# Get IPs
echo "Instance IPs:"
gcloud compute instances list --filter="name~whiteboard OR name=redis" --format="table(name, zone, networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs[0].natIP)"

echo ""
echo "Load Balancer IP:"
gcloud compute forwarding-rules describe whiteboard-forwarding-rule --global --format='get(IPAddress)' 2>/dev/null || echo "Not ready yet"

echo ""
echo "Next steps:"
echo "1. SSH into each whiteboard VM and deploy the application"
echo "2. Run: gcloud compute ssh whiteboard-node-1 --zone=$ZONE"
echo "3. Follow the deployment instructions in deploy-app.sh"
