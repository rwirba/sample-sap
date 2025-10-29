#!/bin/bash
set -euo pipefail

# ========= CONFIG =========
APP_NAME="dashboard"
DOMAIN="ryandemolab.app"
HOSTNAME="${APP_NAME}.${DOMAIN}"
TUNNEL_ID="0e5c75e7-4566-44a9-b988-7a79c9f5e11a"
CRED_FILE="/home/ec2-user/.cloudflared/${TUNNEL_ID}.json"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
SERVICE_NAME="cloudflared-${APP_NAME}.service"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# --- Ensure cloudflared installed ---
if ! command -v cloudflared &>/dev/null; then
  echo "📦 Installing Cloudflared..."
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# --- Verify tunnel credentials exist ---
if [[ ! -f "$CRED_FILE" ]]; then
  echo "❌ Missing tunnel credentials: $CRED_FILE"
  echo "👉 Please download your tunnel JSON (for ID ${TUNNEL_ID}) to ~/.cloudflared/"
  exit 1
fi

# --- Launch dashboard and detect URL ---
echo "🧭 Launching Kubernetes Dashboard..."
nohup minikube dashboard --url > /tmp/minikube-dashboard-url.txt 2>&1 &
sleep 8
URL=$(grep -Eo 'http://127\.0\.0\.1:[0-9]+/api/v1/.*proxy/' /tmp/minikube-dashboard-url.txt | head -n1 || true)

if [[ -z "$URL" ]]; then
  echo "❌ Could not detect dashboard URL."
  echo "Check output: cat /tmp/minikube-dashboard-url.txt"
  exit 1
fi

PORT=$(echo "$URL" | grep -Eo '[0-9]+' | head -n1)
echo "🌐 Dashboard running locally at $URL"
echo "📘 Detected dashboard port: $PORT"

# --- Generate config.yml dynamically ---
sudo mkdir -p "$CONFIG_DIR"
sudo bash -c "cat > $CONFIG_FILE <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}

ingress:
  - hostname: ${HOSTNAME}
    service: http://127.0.0.1:${PORT}/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/
    originRequest:
      noTLSVerify: true
      httpHostHeader: 127.0.0.1
  - service: http_status:404
EOF"

echo "🧩 Updated Cloudflare config: $CONFIG_FILE"

# --- Create systemd service if missing ---
if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}" ]]; then
  echo "🧱 Creating ${SERVICE_NAME} service..."
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
  sudo systemctl enable "${SERVICE_NAME}"
fi

# --- Restart tunnel ---
echo "🔄 Restarting ${SERVICE_NAME}..."
sudo systemctl daemon-reload
sudo systemctl restart "${SERVICE_NAME}"
sleep 3
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

# --- Validate DNS route ---
if ! cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
  echo "🌍 Registering DNS route for ${HOSTNAME}..."
  cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" || true
else
  echo "✅ DNS route already exists for ${HOSTNAME}."
fi

echo "🎯 Dashboard ready at: https://${HOSTNAME}"
