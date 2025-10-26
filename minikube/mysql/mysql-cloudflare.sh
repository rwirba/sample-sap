#!/bin/bash
set -euo pipefail

APP_NAME="mysql"
HOSTNAME="${APP_NAME}.mitechnology.org"
S3_TUNNEL_PATH="s3://ryandevlab-bucket/cloudflare-tunnel.json"
TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"

echo "🚀 Setting up Cloudflare Tunnel for ${APP_NAME}..."

# --- install dependencies ---
sudo dnf install -y awscli jq curl policycoreutils || true

# --- ensure cloudflared ---
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# --- prepare dirs ---
sudo mkdir -p "$TUNNEL_DIR" /root/.cloudflared

# --- get cluster IP ---
if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Missing /etc/minikube/env-info.json. Run global-setup.sh first."
  exit 1
fi
CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)
echo "🌐 Using cluster IP: $CLUSTER_IP"

# --- download tunnel credentials ---
echo "📥 Fetching tunnel credentials for ${APP_NAME}..."
sudo aws s3 cp "$S3_TUNNEL_PATH" "$TUNNEL_DIR/tunnel.json" --quiet
TUNNEL_ID=$(sudo jq -r .TunnelID "$TUNNEL_DIR/tunnel.json")
sudo cp "$TUNNEL_DIR/tunnel.json" "/root/.cloudflared/${TUNNEL_ID}.json"

# --- build config ---
echo "⚙️ Generating config for ${HOSTNAME}..."
sudo bash -c "cat > ${TUNNEL_DIR}/config.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json
ingress:
  - hostname: ${HOSTNAME}
    service: http://${CLUSTER_IP}:3306
  - service: http_status:404
EOF"
sudo chmod 644 "${TUNNEL_DIR}/config.yml"

# --- systemd service ---
echo "🧩 Creating ${SERVICE_NAME}..."
sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME} <<EOF
[Unit]
Description=Cloudflare Tunnel - ${APP_NAME}
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared --config ${TUNNEL_DIR}/config.yml tunnel run
Restart=always
User=root
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF"

# --- reload + enable ---
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 5
sudo systemctl status "${SERVICE_NAME}" --no-pager

echo "✅ Tunnel for ${APP_NAME} ready at https://${HOSTNAME}"


