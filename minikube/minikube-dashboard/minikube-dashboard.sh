#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"

# --- Load environment info ---
if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Missing /etc/minikube/env-info.json. Run global-setup.sh first."
  exit 1
fi

DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
S3_TUNNEL_JSON=$(jq -r .tunnels.dashboard /etc/minikube/env-info.json)
HOSTNAME="${APP_NAME}.${DOMAIN}"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
LOCAL_CF_DIR="/home/ec2-user/.cloudflared"
CRED_FILE="${LOCAL_CF_DIR}/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# --- Ensure directories ---
sudo mkdir -p "$CONFIG_DIR" "$LOCAL_CF_DIR"
sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

# --- Download tunnel credentials from S3 ---
echo "📥 Downloading tunnel credentials from S3..."
aws s3 cp "$S3_TUNNEL_JSON" "$CRED_FILE" --quiet || {
  echo "❌ Failed to download $S3_TUNNEL_JSON"
  exit 1
}

# --- Validate tunnel JSON ---
if ! jq empty "$CRED_FILE" 2>/dev/null; then
  echo "❌ Invalid or missing tunnel credentials JSON: $CRED_FILE"
  exit 1
fi

# --- Extract tunnel ID ---
TUNNEL_ID=$(jq -r .TunnelID "$CRED_FILE")
echo "✅ Tunnel ID: $TUNNEL_ID"

# --- Get Minikube IP ---
CLUSTER_IP=$(minikube ip)
echo "🌐 Minikube IP: $CLUSTER_IP"

# --- Generate Cloudflare config ---
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

# --- Create systemd service ---
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

# --- Reload and start the service ---
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now

# --- Wait and show status ---
sleep 3
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

# --- Register DNS route (if not already) ---
if ! cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
  echo "🌍 Registering DNS route for ${HOSTNAME}..."
  cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" || true
else
  echo "✅ DNS route already exists for ${HOSTNAME}."
fi

echo "✅ Dashboard available at: https://${HOSTNAME}"
#