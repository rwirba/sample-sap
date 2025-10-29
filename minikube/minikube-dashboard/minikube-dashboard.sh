#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"

if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Missing /etc/minikube/env-info.json. Run ./global-setup.sh first."
  exit 1
fi

DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
HOSTNAME="${APP_NAME}.${DOMAIN}"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
TUNNEL_JSON=$(jq -r .tunnels.dashboard /etc/minikube/env-info.json)
CRED_FILE="/home/ec2-user/.cloudflared/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
INGRESS_FILE="/opt/minikube/dashboard-ingress.yml"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

sudo mkdir -p ~/.cloudflared "$CONFIG_DIR"

# ✅ Download credentials JSON from S3
aws s3 cp "$TUNNEL_JSON" "$CRED_FILE" --quiet
sudo chown ec2-user:ec2-user "$CRED_FILE"
sudo chmod 600 "$CRED_FILE"

TUNNEL_ID=$(jq -r .TunnelID "$CRED_FILE")
CLUSTER_IP=$(minikube ip)

# ✅ Generate Cloudflare config
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

# ✅ Create or update systemd service
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

# ✅ Register DNS route (idempotent)
cloudflared tunnel route dns "$TUNNEL_ID" "$HOSTNAME" || true

echo "✅ Dashboard available at: https://${HOSTNAME}"
