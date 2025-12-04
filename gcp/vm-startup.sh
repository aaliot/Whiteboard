#!/bin/bash

# ============================================================
# VM Startup Script - Runs automatically when VM boots
# ============================================================

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Node.js 22 (for development/debugging)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# Get Redis IP from metadata
REDIS_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/redis-ip" -H "Metadata-Flavor: Google" 2>/dev/null || echo "10.0.0.2")

# Create environment file
cat > /home/ubuntu/.env << EOF
REDIS_URL=redis://${REDIS_IP}:6379
WS_PORT=8080
CORS_ORIGIN=*
NEXT_PUBLIC_SOCKET_URL=http://localhost:8080
EOF

chown ubuntu:ubuntu /home/ubuntu/.env

echo "VM setup complete! Redis IP: $REDIS_IP"
echo "To deploy the app, clone your repo and run docker-compose up"
