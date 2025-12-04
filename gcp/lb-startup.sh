#!/bin/bash

# ============================================================
# Load Balancer VM Startup Script
# ============================================================

set -e

apt-get update
apt-get install -y nginx

# Get node IPs from metadata
NODE1_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/node1-ip" -H "Metadata-Flavor: Google")
NODE2_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/node2-ip" -H "Metadata-Flavor: Google")

# Get external IP of this LB
EXTERNAL_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google")

# Create Nginx configuration
cat > /etc/nginx/sites-available/whiteboard << EOF
upstream whiteboard_web {
    least_conn;
    server ${NODE1_IP}:3000;
    server ${NODE2_IP}:3000;
    keepalive 32;
}

upstream whiteboard_socket {
    ip_hash;
    server ${NODE1_IP}:8080;
    server ${NODE2_IP}:8080;
    keepalive 32;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://whiteboard_web;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /socket.io/ {
        proxy_pass http://whiteboard_socket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/whiteboard /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload nginx
nginx -t
systemctl reload nginx
systemctl enable nginx

echo "Nginx load balancer configured!"
echo "Access at: http://${EXTERNAL_IP}"
