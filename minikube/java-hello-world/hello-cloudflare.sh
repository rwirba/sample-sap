#!/bin/bash
set -euo pipefail

# ========== CONFIGURATION ==========
APP_NAME="hello"
HOSTNAME="${APP_NAME}.mitechnology.org"
S3_TUNNEL_PATH="s3://ryandevlab-bucket/cloudflare-tunnel.json"
TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"

# ========== CERTIFICATE HANDLING ==========
USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6 2>/dev/null || echo "$HOME")
USER_CERT_PATH="${USER_HOME}/.cloudflared/cert.pem"
ROOT_CERT_PATH="/root/.cloudflared/cert.pem"

echo "🚀 Setting up Cloudflare Tunnel for ${APP_NAME}..."

echo "📁 Ensuring Cloudflare cert.pem exists..."
if [[ -f "$USER_CERT_PATH" && ! -f "$ROOT_CERT_PATH" ]]; then
  sudo mkdir -p /root/.cloudflared
  sudo cp "$USER_CERT_PATH" "$ROOT_CERT_PATH"
  sudo chmod 600 "$ROOT_CERT_PATH"
  echo "✅ Synced cert.pem from $USER_HOME to /root/.cloudflared"
fi

if [[ ! -f "$ROOT_CERT_PATH" ]]; then
  echo "❌ Missing Cloudflare cert.pem. Run: cloudflared login"
  exit 1
fi
export TUNNEL_ORIGIN_CERT="$ROOT_CERT_PATH"

# ========== INSTALL DEPENDENCIES ==========
sudo dnf install -y awscli jq curl policycoreutils || true

if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
       -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# ========== LOAD CLUSTER INFO ==========
if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Missing /etc/minikube/env-info.json. Run global-setup.sh first."
  exit 1
fi
CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)
echo "🌐 Using Minikube IP: ${CLUSTER_IP}"

# ========== FETCH TUNNEL CREDENTIALS ==========
sudo mkdir -p "$TUNNEL_DIR"
sudo aws s3 cp "$S3_TUNNEL_PATH" "$TUNNEL_DIR/tunnel.json" --quiet
TUNNEL_ID=$(sudo jq -r .TunnelID "$TUNNEL_DIR/tunnel.json")
sudo cp "$TUNNEL_DIR/tunnel.json" "/root/.cloudflared/${TUNNEL_ID}.json"

# ========== CREATE CONFIG ==========
echo "⚙️ Generating ${TUNNEL_DIR}/config.yml..."
sudo bash -c "cat > ${TUNNEL_DIR}/config.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json
ingress:
  - hostname: ${HOSTNAME}
    service: http://${CLUSTER_IP}:80
  - service: http_status:404
EOF"
sudo chmod 644 "${TUNNEL_DIR}/config.yml"

# ========== SYSTEMD SERVICE ==========
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

# ========== ENABLE & START ==========
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 5
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

echo "✅ Tunnel for ${APP_NAME} ready at https://${HOSTNAME}"

# ========== DNS REGISTRATION ==========
echo "🌍 Checking DNS route for ${HOSTNAME}..."
if cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
  echo "✅ DNS route already exists."
else
  echo "🆕 Registering DNS route..."
  cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" && \
  echo "✅ DNS route created for ${HOSTNAME}."
fi
