#!/bin/bash

# ============================================================
# Deploy Monitoring Stack on Monitoring VM
# ============================================================
# Run this after SSH'ing into the monitoring VM

set -e

# Get IPs from metadata
REDIS_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/redis-ip" -H "Metadata-Flavor: Google" 2>/dev/null || echo "10.0.0.2")
NODE1_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/node1-ip" -H "Metadata-Flavor: Google" 2>/dev/null || echo "10.0.0.3")
NODE2_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/node2-ip" -H "Metadata-Flavor: Google" 2>/dev/null || echo "10.0.0.4")
EXTERNAL_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google" 2>/dev/null || echo "localhost")

echo "Setting up monitoring..."
echo "Redis IP: $REDIS_IP"
echo "Node 1 IP: $NODE1_IP"
echo "Node 2 IP: $NODE2_IP"

# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Create monitoring directory
mkdir -p ~/monitoring/grafana/provisioning/dashboards
mkdir -p ~/monitoring/grafana/provisioning/datasources
cd ~/monitoring

# Create Prometheus config
cat > prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: 
        - 'localhost:9100'
        - '${NODE1_IP}:9100'
        - '${NODE2_IP}:9100'

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
EOF

# Create docker-compose
cat > docker-compose.yml << EOF
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    restart: always

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    restart: always

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)(\\$\\$|/)'
    restart: always

  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: redis-exporter
    ports:
      - "9121:9121"
    environment:
      - REDIS_ADDR=redis://${REDIS_IP}:6379
    restart: always

volumes:
  prometheus_data:
  grafana_data:
EOF

# Start monitoring stack
sudo docker compose up -d

echo ""
echo "============================================"
echo "Monitoring Setup Complete!"
echo "============================================"
echo ""
echo "Grafana: http://${EXTERNAL_IP}:3001"
echo "  - Username: admin"
echo "  - Password: admin123"
echo ""
echo "Prometheus: http://${EXTERNAL_IP}:9090"
echo ""
echo "Add Prometheus as a data source in Grafana:"
echo "  URL: http://prometheus:9090"
