#!/bin/bash

# ============================================================
# Cleanup Script - Delete All GCP Resources
# ============================================================
# WARNING: This will delete all resources created by setup.sh

set -e

PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
REGION="europe-west2"
ZONE="${REGION}-a"
NETWORK_NAME="whiteboard-network"

echo "============================================"
echo "Deleting GCP Private Cloud Resources"
echo "============================================"
echo "Project: $PROJECT_ID"
echo ""
read -p "Are you sure you want to delete ALL resources? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

gcloud config set project $PROJECT_ID

# Delete VMs
echo "Deleting VMs..."
gcloud compute instances delete redis-server --zone=$ZONE --quiet 2>/dev/null || true
gcloud compute instances delete whiteboard-node-1 --zone=$ZONE --quiet 2>/dev/null || true
gcloud compute instances delete whiteboard-node-2 --zone=${REGION}-b --quiet 2>/dev/null || true
gcloud compute instances delete whiteboard-lb --zone=$ZONE --quiet 2>/dev/null || true
gcloud compute instances delete monitoring --zone=$ZONE --quiet 2>/dev/null || true

# Delete load balancer resources
echo "Deleting Load Balancer resources..."
gcloud compute forwarding-rules delete whiteboard-forwarding-rule --global --quiet 2>/dev/null || true
gcloud compute target-http-proxies delete whiteboard-http-proxy --quiet 2>/dev/null || true
gcloud compute url-maps delete whiteboard-lb --quiet 2>/dev/null || true
gcloud compute backend-services delete whiteboard-backend --global --quiet 2>/dev/null || true
gcloud compute health-checks delete whiteboard-health-check --quiet 2>/dev/null || true
gcloud compute instance-groups unmanaged delete whiteboard-group --zone=$ZONE --quiet 2>/dev/null || true

# Delete firewall rules
echo "Deleting Firewall Rules..."
gcloud compute firewall-rules delete ${NETWORK_NAME}-allow-internal --quiet 2>/dev/null || true
gcloud compute firewall-rules delete ${NETWORK_NAME}-allow-ssh --quiet 2>/dev/null || true
gcloud compute firewall-rules delete ${NETWORK_NAME}-allow-web --quiet 2>/dev/null || true
gcloud compute firewall-rules delete ${NETWORK_NAME}-allow-health-check --quiet 2>/dev/null || true
gcloud compute firewall-rules delete ${NETWORK_NAME}-allow-grafana --quiet 2>/dev/null || true

# Delete subnet and network
echo "Deleting Network..."
gcloud compute networks subnets delete whiteboard-subnet --region=$REGION --quiet 2>/dev/null || true
gcloud compute networks delete $NETWORK_NAME --quiet 2>/dev/null || true

echo ""
echo "============================================"
echo "Cleanup Complete!"
echo "============================================"
