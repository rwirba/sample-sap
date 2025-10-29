#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"
HOSTNAME="${APP_NAME}.ryandemolab.app"
TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
ROOT_CERT_PATH="/home/ec2-user/.cloudflared/cert.pem"
GLOBAL_ENV_INFO="/etc/minikube/env-info.json"

echo "🚀 Setting up Cloudflare Tunnel for Kubernetes Dashboard..."

# --- Ensure cloudflared installed ---
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
       -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# --- Ensure Cloudflare cert exists ---
if [[ ! -f "$ROOT_CERT_PATH" ]]; then
  echo "❌ Missing Cloudflare cert.pem."
  echo "👉 Run: cloudflared login (then select your domain)."
  exit 1
fi

# --- Ensure tunnel credentials exist or reuse from global setup ---
GLOBAL_TUNNEL_ID=""
GLOBAL_TUNNEL_FILE=""

if [[ -f "$GLOBAL_ENV_INFO" ]]; then
  GLOBAL_TUNNEL_ID=$(jq -r .tunnel_id "$GLOBAL_ENV_INFO" 2>/dev/null || true)
  [[ "$GLOBAL_TUNNEL_ID" != "null" && -n "$GLOBAL_TUNNEL_ID" ]] && \
  GLOBAL_TUNNEL_FILE="/root/.cloudflared/${GLOBAL_TUNNEL_ID}.json"
fi

TUNNEL_CRED_PATH="/home/ec2-user/.cloudflared/${APP_NAME}-tunnel.json"

if [[ ! -f "$TUNNEL_CRED_PATH" ]]; then
  # If a global tunnel exists, reuse it
  if [[ -n "$GLOBAL_TUNNEL_ID" && -f "$GLOBAL_TUNNEL_FILE" ]]; then
    echo "♻️ Reusing global Cloudflare tunnel credentials..."
    sudo cp "$GLOBAL_TUNNEL_FILE" "$TUNNEL_CRED_PATH"
  else
    # Otherwise create a local tunnel if none exists
    if cloudflared tunnel list 2>/dev/null | grep -q "${APP_NAME}-tunnel"; then
      echo "✅ Existing tunnel '${APP_NAME}-tunnel' found, skipping creation."
    else
      echo "🆕 Creating new Cloudflare tunnel: ${APP_NAME}-tunnel"
      cloudflared tunnel create "${APP_NAME}-tunnel"
    fi
  fi
else
  echo "✅ Using existing local tunnel credentials at $TUNNEL_CRED_PATH"
fi

# --- Get Tunnel ID ---
TUNNEL_ID=$(cloudflared tunnel list | grep "${APP_NAME}-tunnel" | awk '{print $2}' | head -n1)
if [[ -z "$TUNNEL_ID" ]]; then
  echo "❌ Could not detect tunnel ID for ${APP_NAME}-tunnel."
  exit 1
fi
echo "📘 Tunnel ID: $TUNNEL_ID"

# --- Launch Kubernetes Dashboard ---
if ! pgrep -f "minikube dashboard" >/dev/null 2>&1; then
  echo "🧭 Launching Kubernetes Dashboard..."
  nohup minikube dashboard --port=8001 --url >/tmp/dashboard-url.txt 2>&1 &
  sleep 6
else
  echo "✅ Dashboard process already running."
fi

URL=$(grep -o 'http://127.0.0.1:[0-9]\+' /tmp/dashboard-url.txt | head -n1 || echo "http://127.0.0.1:8001")
echo "🌐 Dashboard local URL: $URL"

# --- Build Cloudflare Tunnel Config ---
sudo mkdir -p "$TUNNEL_DIR"
sudo bash -c "cat > ${TUNNEL_DIR}/config.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${TUNNEL_CRED_PATH}
ingress:
  - hostname: ${HOSTNAME}
    service: ${URL}
  - service: http_status:404
EOF"

# --- Create Systemd Service (idempotent) ---
echo "🧩 Ensuring ${SERVICE_NAME} is configured..."
if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}" ]]; then
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
fi

# --- Start & enable tunnel service ---
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 3
if systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "✅ ${SERVICE_NAME} is running."
else
  echo "⚠️ ${SERVICE_NAME} failed to start — check logs via:"
  echo "   sudo journalctl -u ${SERVICE_NAME} -e"
fi

# --- Register DNS Route (idempotent) ---
echo "🌍 Checking DNS route for ${HOSTNAME}..."
if cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
  echo "✅ DNS route for ${HOSTNAME} already exists."
else
  echo "🆕 Registering new DNS route for ${HOSTNAME}..."
  cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" && \
  echo "✅ DNS route created for ${HOSTNAME}."
fi

echo "🎯 Dashboard available securely at: https://${HOSTNAME}"
