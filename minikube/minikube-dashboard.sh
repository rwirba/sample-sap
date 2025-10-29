#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"
HOSTNAME="${APP_NAME}.ryandemolab.app"
TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
ROOT_CERT_PATH="/home/ec2-user/.cloudflared/cert.pem"
TUNNEL_CRED_PATH="/home/ec2-user/.cloudflared/${APP_NAME}-tunnel.json"

echo "🚀 Setting up Cloudflare Tunnel for Kubernetes Dashboard..."

# --- Ensure Cloudflared installed ---
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# --- Ensure cert.pem exists ---
if [[ ! -f "$ROOT_CERT_PATH" ]]; then
  echo "❌ Missing Cloudflare cert.pem."
  echo "👉 Run: cloudflared login (then select your domain)."
  exit 1
fi

# --- Create tunnel if not exists ---
if [[ ! -f "$TUNNEL_CRED_PATH" ]]; then
  echo "🆕 Creating new Cloudflare tunnel: ${APP_NAME}-tunnel"
  cloudflared tunnel create "${APP_NAME}-tunnel"
fi

# --- Get Tunnel ID ---
TUNNEL_ID=$(cloudflared tunnel list | grep "${APP_NAME}-tunnel" | awk '{print $2}' | head -n1)
if [[ -z "$TUNNEL_ID" ]]; then
  echo "❌ Could not detect tunnel ID for ${APP_NAME}-tunnel."
  exit 1
fi
echo "📘 Tunnel ID: $TUNNEL_ID"

# --- Launch Kubernetes Dashboard ---
echo "🧭 Launching Kubernetes Dashboard..."
nohup minikube dashboard --port=8001 --url >/tmp/dashboard-url.txt 2>&1 &
sleep 5
URL=$(grep -o 'http://127.0.0.1:[0-9]\+' /tmp/dashboard-url.txt | head -n1 || echo "http://127.0.0.1:8001")

echo "🌐 Dashboard local URL: $URL"

# --- Build Tunnel Config ---
sudo mkdir -p "$TUNNEL_DIR"
sudo bash -c "cat > ${TUNNEL_DIR}/config.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${TUNNEL_CRED_PATH}
ingress:
  - hostname: ${HOSTNAME}
    service: ${URL}
  - service: http_status:404
EOF"

# --- Create Systemd Service ---
echo "🧩 Creating ${SERVICE_NAME}..."
sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME} <<EOF
[Unit]
Description=Cloudflare Tunnel - ${APP_NAME}
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared --config ${TUNNEL_DIR}/config.yml tunnel run
Restart=always
User=ec2-user
Environment=HOME=/home/ec2-user

[Install]
WantedBy=multi-user.target
EOF"

# --- Start Tunnel Service ---
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 3
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

# --- Register DNS route ---
echo "🌍 Checking DNS route for ${HOSTNAME}..."
if cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
  echo "✅ DNS route for ${HOSTNAME} already exists."
else
  echo "🆕 Registering new DNS route for ${HOSTNAME}..."
  cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" && \
  echo "✅ DNS route created for ${HOSTNAME}."
fi

echo "🎯 Dashboard available securely at: https://${HOSTNAME}"
