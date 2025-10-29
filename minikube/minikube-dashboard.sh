#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"
DOMAIN="ryandemolab.app"
HOSTNAME="${APP_NAME}.${DOMAIN}"
TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
CERT_PATH="/home/ec2-user/.cloudflared/cert.pem"
GLOBAL_ENV_INFO="/etc/minikube/env-info.json"

echo "🚀 Setting up Cloudflare Tunnel for ${APP_NAME}.${DOMAIN}..."

# ============================================================
# 1️⃣ Ensure cloudflared installed
# ============================================================
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
       -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# ============================================================
# 2️⃣ Verify cert.pem (Cloudflare login)
# ============================================================
if [[ ! -f "$CERT_PATH" ]]; then
  echo "❌ Missing Cloudflare cert.pem."
  echo "👉 Run 'cloudflared login' (select ${DOMAIN}) before re-running this script."
  exit 1
fi

# ============================================================
# 3️⃣ Detect or create Cloudflare tunnel (re-use global one)
# ============================================================
GLOBAL_TUNNEL_ID=""
if [[ -f "$GLOBAL_ENV_INFO" ]]; then
  GLOBAL_TUNNEL_ID=$(jq -r '.tunnel_id // empty' "$GLOBAL_ENV_INFO" 2>/dev/null || true)
fi

# If global tunnel is known, reuse it
if [[ -n "$GLOBAL_TUNNEL_ID" ]]; then
  echo "♻️ Reusing existing global tunnel ID: $GLOBAL_TUNNEL_ID"
else
  echo "🆕 Creating new Cloudflare tunnel..."
  cloudflared tunnel create "${APP_NAME}-tunnel" || true
  GLOBAL_TUNNEL_ID=$(cloudflared tunnel list | grep "${APP_NAME}-tunnel" | awk '{print $2}' | head -n1)
  [[ -z "$GLOBAL_TUNNEL_ID" ]] && { echo "❌ Failed to detect tunnel ID."; exit 1; }
fi

# ============================================================
# 4️⃣ Locate the actual credentials file automatically
# ============================================================
CRED_FILE=$(find /home/ec2-user/.cloudflared -maxdepth 1 -type f -name "${GLOBAL_TUNNEL_ID}.json" | head -n1 || true)
if [[ -z "$CRED_FILE" ]]; then
  echo "❌ Could not find credentials for tunnel ${GLOBAL_TUNNEL_ID}."
  echo "Try re-running: cloudflared tunnel create ${APP_NAME}-tunnel"
  exit 1
fi
echo "🔐 Using credentials file: $CRED_FILE"

# ============================================================
# 5️⃣ Launch Kubernetes dashboard (auto-reuse)
# ============================================================
if ! pgrep -f "minikube dashboard" >/dev/null 2>&1; then
  echo "🧭 Launching Kubernetes Dashboard..."
  nohup minikube dashboard --port=8001 --url >/tmp/dashboard-url.txt 2>&1 &
  sleep 5
else
  echo "✅ Dashboard already running."
fi

URL=$(grep -o 'http://127.0.0.1:[0-9]\+' /tmp/dashboard-url.txt | head -n1 || echo "http://127.0.0.1:8001")
echo "🌐 Dashboard local URL: $URL"

# ============================================================
# 6️⃣ Build config.yml safely (always correct)
# ============================================================
sudo mkdir -p "$TUNNEL_DIR"
sudo bash -c "cat > ${TUNNEL_DIR}/config.yml <<EOF
tunnel: ${GLOBAL_TUNNEL_ID}
credentials-file: ${CRED_FILE}
ingress:
  - hostname: ${HOSTNAME}
    service: ${URL}
  - service: http_status:404
EOF"
echo "🧩 Config file updated: ${TUNNEL_DIR}/config.yml"

# ============================================================
# 7️⃣ Create or refresh systemd service
# ============================================================
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

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 3

if systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "✅ ${SERVICE_NAME} is active and running."
else
  echo "⚠️ ${SERVICE_NAME} failed — check logs:"
  echo "   sudo journalctl -u ${SERVICE_NAME} -e | tail -n 30"
  exit 1
fi

# ============================================================
# 8️⃣ Ensure DNS mapping exists
# ============================================================
if cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
  echo "✅ DNS route for ${HOSTNAME} already exists."
else
  echo "🌍 Registering DNS route for ${HOSTNAME}..."
  cloudflared tunnel route dns "${GLOBAL_TUNNEL_ID}" "${HOSTNAME}"
fi

echo "🎯 Dashboard available securely at: https://${HOSTNAME}"
