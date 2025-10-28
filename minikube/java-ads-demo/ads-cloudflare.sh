#!/bin/bash
set -euo pipefail

APP_NAME="ads"
HOSTNAME="${APP_NAME}.mitechnology.org"
S3_TUNNEL_PATH="s3://ryandevlab-bucket/cloudflare-tunnel.json"
TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
ROOT_CERT_PATH="/root/.cloudflared/cert.pem"

echo "🚀 Setting up Cloudflare Tunnel for ${APP_NAME}..."

# --- Detect invoking user home ---
USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6 2>/dev/null || echo "$HOME")
USER_CERT_PATH="${USER_HOME}/.cloudflared/cert.pem"

# --- Preflight: sync cert from user home to root ---
if [[ -f "$USER_CERT_PATH" && ! -f "$ROOT_CERT_PATH" ]]; then
  echo "📁 Copying Cloudflare cert.pem from $USER_HOME to /root..."
  sudo mkdir -p /root/.cloudflared
  sudo cp "$USER_CERT_PATH" "$ROOT_CERT_PATH"
  sudo chmod 600 "$ROOT_CERT_PATH"
  echo "✅ Synced Cloudflare cert.pem from $USER_HOME to /root for root/systemd access."
fi

# --- Validate cert ---
if ! sudo test -f "$ROOT_CERT_PATH"; then
  echo "❌ Missing Cloudflare login certificate."
  echo "👉 Run: cloudflared login (then select your domain)."
  exit 1
fi

export TUNNEL_ORIGIN_CERT="$ROOT_CERT_PATH"

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

# --- fetch tunnel credentials ---
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
    service: http://${CLUSTER_IP}:30200
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

# --- reload + start ---
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 5
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

echo "✅ Tunnel for ${APP_NAME} ready at https://${HOSTNAME}"

# --- Verify or register DNS route ---
if cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
  echo "✅ DNS route for ${HOSTNAME} already exists."
else
  echo "🆕 Registering new DNS route for ${HOSTNAME}..."
  cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" && \
  echo "✅ DNS route created for ${HOSTNAME}."
fi
