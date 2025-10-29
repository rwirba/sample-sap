#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"
DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
HOSTNAME="${APP_NAME}.${DOMAIN}"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
S3_TUNNEL_JSON=$(jq -r .tunnels.dashboard /etc/minikube/env-info.json)
LOCAL_CF_DIR="/home/ec2-user/.cloudflared"
CRED_FILE="${LOCAL_CF_DIR}/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
INGRESS_FILE="/opt/minikube/dashboard-ingress.yml"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# Ensure required directories exist
sudo mkdir -p "$CONFIG_DIR" "$LOCAL_CF_DIR"
sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

# Download the tunnel JSON from S3
echo "📥 Downloading tunnel credentials from S3..."
aws s3 cp "$S3_TUNNEL_JSON" "$CRED_FILE" --quiet

# Validate the JSON file
if ! jq empty "$CRED_FILE" 2>/dev/null; then
  echo "❌ Invalid or missing tunnel credentials JSON: $CRED_FILE"
  exit 1
fi

# Extract Tunnel ID
TUNNEL_ID=$(jq -r .TunnelID "$CRED_FILE")
echo "✅ Tunnel ID: $TUNNEL_ID"

# Detect Minikube IP
CLUSTER_IP=$(minikube ip)

# Write Cloudflare config
sudo bash -c "cat > ${CONFIG_FILE} <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}
ingress:
  - hostname: ${HOSTNAME}
    service: http://${CLUSTER_IP}:80
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF"

# Create or update systemd service
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

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 3

# Register DNS route if needed
cloudflared tunnel route dns "$TUNNEL_ID" "$HOSTNAME" || true

echo "✅ Dashboard available at: https://${HOSTNAME}"
