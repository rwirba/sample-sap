#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"
HOSTNAME="${APP_NAME}.ryandemolab.app"
TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
ROOT_CERT_PATH="/home/ec2-user/.cloudflared/cert.pem"

echo "Setting up Cloudflare Tunnel for Kubernetes Dashboard..."

# --- Ensure Cloudflared installed ---
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# --- Ensure cert.pem exists ---
if [[ ! -f "$ROOT_CERT_PATH" ]]; then
  echo "Missing Cloudflare cert.pem."
  echo "Run: cloudflared login (then select your domain)."
  exit 1
fi

# --- Start Kubernetes Dashboard ---
echo "Launching Kubernetes Dashboard..."
nohup minikube dashboard --port=8001 --url >/tmp/dashboard-url.txt 2>&1 &
sleep 5
URL=$(grep -o 'http://127.0.0.1:[0-9]\+' /tmp/dashboard-url.txt | head -n1 || echo "http://127.0.0.1:8001")

echo "Dashboard local URL: $URL"

# --- Create config directory ---
sudo mkdir -p "$TUNNEL_DIR"
sudo bash -c "cat > ${TUNNEL_DIR}/config.yml <<EOF
tunnel: ${APP_NAME}-tunnel
credentials-file: /home/ec2-user/.cloudflared/${APP_NAME}-tunnel.json
ingress:
  - hostname: ${HOSTNAME}
    service: ${URL}
  - service: http_status:404
EOF"

# --- Create Systemd Service for Tunnel ---
echo "Creating ${SERVICE_NAME}..."
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

# --- Reload systemd and start tunnel ---
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 3
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

echo "Dashboard available securely at: https://${HOSTNAME}"
# 
