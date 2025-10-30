#!/bin/bash
set -euo pipefail

APP_NAME="hello"
DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
HOSTNAME="${APP_NAME}.${DOMAIN}"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
TUNNEL_JSON="s3://ryandevlab-bucket/cloudflare-tunnels/${APP_NAME}-tunnel.json"
CRED_FILE="/home/ec2-user/.cloudflared/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."
sudo mkdir -p ~/.cloudflared "$CONFIG_DIR"

# ✅ Download from S3
aws s3 cp "$TUNNEL_JSON" "$CRED_FILE" --quiet
echo "📥 Downloaded tunnel credentials from S3."

TUNNEL_ID=$(jq -r .TunnelID "$CRED_FILE")
CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)

sudo bash -c "cat > ${CONFIG_FILE} <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}
ingress:
  - hostname: ${HOSTNAME}
    service: http://${CLUSTER_IP}:82
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF"

sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME} <<EOF
[Unit]
Description=Cloudflare Tunnel - ${APP_NAME}
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared --config ${CONFIG_FILE} tunnel run
Restart=always
User=ec2-user
Environment=HOME=/home/ec2-user

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 3
cloudflared tunnel route dns "$TUNNEL_ID" "$HOSTNAME" || true

echo "✅ Hello app available at: https://${HOSTNAME}"
