#!/bin/bash
set -euo pipefail

MYSQL_HOSTNAME="mysql.mitechnology.org"
CLUSTER_IP=$(minikube ip)
TUNNEL_ID=$(sudo jq -r .TunnelID /root/.cloudflared/tunnel.json)

echo "🔗 Adding MySQL tunnel config to Cloudflare..."
sudo bash -c "cat >> /etc/cloudflared/config.yml <<EOF
  - hostname: $MYSQL_HOSTNAME
    service: tcp://$CLUSTER_IP:3306
EOF"

sudo systemctl restart cloudflared
sudo systemctl status cloudflared --no-pager

echo "✅ Cloudflare DNS tunnel updated for MySQL."
