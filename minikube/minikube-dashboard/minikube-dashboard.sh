# #!/bin/bash
# set -euo pipefail

# # ========= CONFIG =========
# APP_NAME="dashboard"
# DOMAIN="ryandemolab.app"
# HOSTNAME="${APP_NAME}.${DOMAIN}"
# TUNNEL_ID="0e5c75e7-4566-44a9-b988-7a79c9f5e11a"
# CRED_FILE="/home/ec2-user/.cloudflared/${TUNNEL_ID}.json"
# CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
# CONFIG_FILE="${CONFIG_DIR}/config.yml"
# SERVICE_NAME="cloudflared-${APP_NAME}.service"

# echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# # --- Ensure cloudflared installed ---
# if ! command -v cloudflared &>/dev/null; then
#   echo "📦 Installing Cloudflared..."
#   ARCH=$(uname -m)
#   [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
#   sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
#   sudo chmod +x /usr/local/bin/cloudflared
# fi

# # --- Verify tunnel credentials ---
# if [[ ! -f "$CRED_FILE" ]]; then
#   echo "❌ Missing tunnel credentials: $CRED_FILE"
#   echo "👉 Please download your tunnel JSON (for ID ${TUNNEL_ID}) to ~/.cloudflared/"
#   exit 1
# fi

# # --- Detect Minikube IP ---
# CLUSTER_IP=$(minikube ip)
# if [[ -z "$CLUSTER_IP" ]]; then
#   echo "❌ Could not detect Minikube cluster IP."
#   exit 1
# fi
# echo "🌐 Using Minikube IP: $CLUSTER_IP"

# # --- Create Cloudflare config directory ---
# sudo mkdir -p "$CONFIG_DIR"

# # --- Generate static config ---
# sudo bash -c "cat > ${CONFIG_FILE} <<EOF
# tunnel: ${TUNNEL_ID}
# credentials-file: ${CRED_FILE}
# ingress:
#   - hostname: ${HOSTNAME}
#     service: http://${CLUSTER_IP}:80
#     originRequest:
#       noTLSVerify: true
#   - service: http_status:404
# EOF"

# echo "🧩 Updated Cloudflare config: $CONFIG_FILE"

# # --- Create systemd service if missing ---
# if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}" ]]; then
#   echo "🧱 Creating ${SERVICE_NAME} service..."
#   sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME} <<EOF
# [Unit]
# Description=Cloudflare Tunnel - ${APP_NAME}
# After=network.target

# [Service]
# ExecStart=/usr/local/bin/cloudflared --config ${CONFIG_FILE} tunnel run
# Restart=always
# User=ec2-user
# Environment=HOME=/home/ec2-user

# [Install]
# WantedBy=multi-user.target
# EOF"
#   sudo systemctl daemon-reload
#   sudo systemctl enable "${SERVICE_NAME}"
# fi

# # --- Restart and verify ---
# echo "🔄 Restarting ${SERVICE_NAME}..."
# sudo systemctl daemon-reload
# sudo systemctl restart "${SERVICE_NAME}"
# sleep 3
# sudo systemctl status "${SERVICE_NAME}" --no-pager || true

# # --- Ensure DNS route exists ---
# if ! cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
#   echo "🌍 Registering DNS route for ${HOSTNAME}..."
#   cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" || true
# else
#   echo "✅ DNS route already exists for ${HOSTNAME}."
# fi

# echo "🎯 Dashboard available at: https://${HOSTNAME}"


#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"
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
sudo cp "$TUNNEL_JSON" "$CRED_FILE"
TUNNEL_ID=$(jq -r .TunnelID "$CRED_FILE")

CLUSTER_IP=$(minikube ip)

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

echo "✅ Dashboard available at: https://${HOSTNAME}"
