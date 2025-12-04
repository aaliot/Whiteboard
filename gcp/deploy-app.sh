#!/bin/bash

# ============================================================
# Deploy Whiteboard Application to a GCP VM
# ============================================================
# Run this script after SSH'ing into a whiteboard VM
# Usage: ./deploy-app.sh [REDIS_IP]

set -e

# Get Redis IP from argument or metadata
REDIS_IP="${1:-$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/redis-ip" -H "Metadata-Flavor: Google" 2>/dev/null)}"

if [ -z "$REDIS_IP" ]; then
    echo "Error: Redis IP not provided and not found in metadata"
    echo "Usage: ./deploy-app.sh <REDIS_IP>"
    exit 1
fi

echo "============================================"
echo "Deploying Whiteboard Application"
echo "============================================"
echo "Redis IP: $REDIS_IP"
echo ""

# Create app directory in current user's home
APP_DIR="$HOME/whiteboard-app"
mkdir -p $APP_DIR
cd $APP_DIR

# Clone the repository (replace with your repo URL)
if [ ! -d ".git" ]; then
    echo "Cloning repository..."
    git clone https://github.com/aaliot/Whiteboard.git .
else
    echo "Updating repository..."
    git pull origin main
fi

# Get the external IP of this VM for CORS
EXTERNAL_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google" 2>/dev/null || echo "localhost")

# Create production docker-compose override
cat > docker-compose.prod.yml << EOF
services:
  socket:
    build: ./server
    environment:
      REDIS_URL: redis://${REDIS_IP}:6379
      WS_PORT: 8080
      CORS_ORIGIN: "*"
    ports:
      - "8080:8080"
    restart: always

  web:
    build: .
    environment:
      NEXT_PUBLIC_SOCKET_URL: http://${EXTERNAL_IP}:8080
    ports:
      - "3000:3000"
    depends_on:
      - socket
    restart: always
EOF

# Stop existing containers
echo "Stopping existing containers..."
docker compose -f docker-compose.prod.yml down 2>/dev/null || true

# Build and start containers
echo "Building and starting containers..."
docker compose -f docker-compose.prod.yml up --build -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 10

# Check status
echo ""
echo "============================================"
echo "Deployment Complete!"
echo "============================================"
echo ""
echo "Container Status:"
docker compose -f docker-compose.prod.yml ps

echo ""
echo "Access your whiteboard at:"
echo "  - http://${EXTERNAL_IP}:3000"
echo ""
echo "WebSocket server at:"
echo "  - http://${EXTERNAL_IP}:8080"
echo ""
echo "View logs with: docker compose -f docker-compose.prod.yml logs -f"
