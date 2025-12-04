# GCP Private Cloud Deployment Guide

This guide explains how to deploy the Whiteboard application on Google Cloud Platform as a private cloud.

## Architecture Overview

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                    GCP Private Cloud                      │
                    │                   (VPC: whiteboard-network)               │
                    │                                                           │
   Users ──────────►│  ┌─────────────────┐                                     │
                    │  │  Load Balancer   │                                     │
                    │  │  (Nginx/GCP LB)  │                                     │
                    │  │  Port 80         │                                     │
                    │  └────────┬─────────┘                                     │
                    │           │                                               │
                    │     ┌─────┴─────┐                                         │
                    │     ▼           ▼                                         │
                    │  ┌──────────┐  ┌──────────┐                              │
                    │  │ Node 1   │  │ Node 2   │                              │
                    │  │ Web:3000 │  │ Web:3000 │                              │
                    │  │ WS:8080  │  │ WS:8080  │         ┌──────────────┐     │
                    │  └────┬─────┘  └────┬─────┘         │  Monitoring  │     │
                    │       │             │               │  Prometheus  │     │
                    │       └──────┬──────┘               │  Grafana     │     │
                    │              │                      │  Port 3001   │     │
                    │              ▼                      └──────────────┘     │
                    │       ┌──────────────┐                                   │
                    │       │    Redis     │◄──── Shared State                │
                    │       │   Port 6379  │      (Consistency)               │
                    │       └──────────────┘                                   │
                    │                                                          │
                    └──────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose | GCP Resource |
|-----------|---------|--------------|
| Redis Server | Shared state for consistency | Compute Engine VM |
| Whiteboard Node 1 | App instance for user group 1 | Compute Engine VM |
| Whiteboard Node 2 | App instance for user group 2 | Compute Engine VM |
| Load Balancer | Traffic distribution | Nginx on VM or GCP HTTP LB |
| Monitoring | Resource metrics | Prometheus + Grafana |

## Prerequisites

1. **GCP Account** with billing enabled
2. **gcloud CLI** installed and authenticated
3. **GCP Project** created

```bash
# Install gcloud CLI (if not installed)
# https://cloud.google.com/sdk/docs/install

# Authenticate
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

## Step-by-Step Deployment

### Step 1: Upload Scripts to Cloud Shell

Open [Google Cloud Shell](https://shell.cloud.google.com/) and upload the `gcp/` folder, or clone your repository:

```bash
git clone https://github.com/aaliot/Whiteboard.git
cd Whiteboard/gcp
```

### Step 2: Run Infrastructure Setup

```bash
# Set your project ID
export GCP_PROJECT_ID="your-project-id"

# Make scripts executable
chmod +x *.sh

# Run main setup (creates VMs, network, firewall rules)
./setup.sh
```

This creates:
- VPC Network with subnet (10.0.0.0/24)
- Firewall rules for SSH, HTTP, Redis
- 3 VMs: redis-server, whiteboard-node-1, whiteboard-node-2

### Step 3: Deploy Application to Nodes

SSH into each whiteboard node and deploy:

```bash
# Node 1
gcloud compute ssh whiteboard-node-1 --zone=europe-west2-a

# Inside the VM:
git clone https://github.com/aaliot/Whiteboard.git
cd Whiteboard/gcp
chmod +x deploy-app.sh
./deploy-app.sh REDIS_INTERNAL_IP
```

Repeat for Node 2:
```bash
gcloud compute ssh whiteboard-node-2 --zone=europe-west2-b
# Same deployment steps...
```

### Step 4: Setup Load Balancer

```bash
# From Cloud Shell
./setup-loadbalancer.sh
```

Or use GCP's built-in HTTP Load Balancer through the Console.

### Step 5: Setup Monitoring

```bash
# Create monitoring VM
./setup-monitoring.sh

# SSH into monitoring VM
gcloud compute ssh monitoring --zone=europe-west2-a

# Deploy monitoring stack
cd ~/
# Download and run deploy-monitoring.sh
```

## Accessing Your Deployment

After deployment, get the external IPs:

```bash
gcloud compute instances list --format="table(name, zone, EXTERNAL_IP)"
```

| Service | URL |
|---------|-----|
| Whiteboard (via LB) | `http://LOAD_BALANCER_IP` |
| Whiteboard Node 1 | `http://NODE1_EXTERNAL_IP:3000` |
| Whiteboard Node 2 | `http://NODE2_EXTERNAL_IP:3000` |
| Grafana | `http://MONITORING_IP:3001` (admin/admin123) |
| Prometheus | `http://MONITORING_IP:9090` |

## Verifying Consistency

1. Open the whiteboard in two different browsers
2. Connect one to Node 1, another to Node 2
3. Draw on one - it should appear on the other instantly
4. This works because both nodes share Redis for state

## Scaling (Auto-scaling)

To add more nodes:

```bash
# Create a new node
gcloud compute instances create whiteboard-node-3 \
    --zone=europe-west2-c \
    --machine-type=e2-medium \
    --network=whiteboard-network \
    --subnet=whiteboard-subnet \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --tags=whiteboard-server,http-server

# SSH and deploy app
gcloud compute ssh whiteboard-node-3 --zone=europe-west2-c
```

For automatic scaling, consider using:
- **GCP Managed Instance Groups** with auto-scaling policies
- **Google Kubernetes Engine (GKE)** for container orchestration

## Cleanup

To delete all resources:

```bash
# Delete VMs
gcloud compute instances delete redis-server whiteboard-node-1 whiteboard-node-2 whiteboard-lb monitoring --zone=europe-west2-a --quiet
gcloud compute instances delete whiteboard-node-2 --zone=europe-west2-b --quiet

# Delete firewall rules
gcloud compute firewall-rules delete whiteboard-network-allow-internal whiteboard-network-allow-ssh whiteboard-network-allow-web whiteboard-network-allow-health-check --quiet

# Delete network
gcloud compute networks subnets delete whiteboard-subnet --region=europe-west2 --quiet
gcloud compute networks delete whiteboard-network --quiet
```

## Cost Estimation

| Resource | Type | Estimated Monthly Cost |
|----------|------|----------------------|
| 3x Compute VMs | e2-medium | ~$75 |
| 1x LB VM | e2-small | ~$15 |
| 1x Monitoring VM | e2-medium | ~$25 |
| Network Egress | Variable | ~$10 |
| **Total** | | **~$125/month** |

Use GCP's [Pricing Calculator](https://cloud.google.com/products/calculator) for exact estimates.

## Troubleshooting

### Can't connect to whiteboard
```bash
# Check if containers are running
docker ps

# Check logs
docker compose logs -f
```

### Nodes not syncing
```bash
# Check Redis connectivity
redis-cli -h REDIS_IP ping

# Check WebSocket server logs
docker logs socket
```

### VM won't start
```bash
# Check VM status
gcloud compute instances describe whiteboard-node-1 --zone=europe-west2-a

# View serial port output (startup logs)
gcloud compute instances get-serial-port-output whiteboard-node-1 --zone=europe-west2-a
```
