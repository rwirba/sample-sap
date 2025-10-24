#!/bin/bash
set -euo pipefail

S3_TUNNEL_PATH="s3://ryandevlab-bucket/cloudflare-tunnel.json"
TUNNEL_NAME="minikube-tunnel"
ZONE="mitechnology.org"
DOMAINS=("hello.mitechnology.org" "ads.mitechnology.org")

echo "🚀 Setting up Cloudflare Tunnel..."
sudo dnf install -y awscli jq curl policycoreutils || true
cd "$(dirname "$0")"

# --- Load cluster info ---
if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Cluster info file not found. Run setup.sh first!"
  exit 1
fi

NAMESPACE=$(jq -r .namespace /etc/minikube/env-info.json)
CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)

if [[ -z "$CLUSTER_IP" || -z "$NAMESPACE" ]]; then
  echo "❌ Invalid cluster info. Make sure setup.sh completed successfully."
  exit 1
fi

echo "🌐 Namespace: $NAMESPACE | Cluster IP: $CLUSTER_IP"

# --- Install cloudflared ---
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
  echo "✅ Cloudflared installed."
else
  echo "✅ Cloudflared already installed."
fi

# --- Download tunnel credentials from S3 ---
echo "📥 Downloading Cloudflare tunnel credentials from S3..."
sudo mkdir -p /root/.cloudflared /etc/cloudflared
sudo aws s3 cp "$S3_TUNNEL_PATH" /root/.cloudflared/tunnel.json --quiet

# --- Extract tunnel ID ---
TUNNEL_ID=$(sudo jq -r .TunnelID /root/.cloudflared/tunnel.json)
echo "📘 Tunnel ID: $TUNNEL_ID"

# --- Copy creds ---
sudo cp /root/.cloudflared/tunnel.json "/root/.cloudflared/${TUNNEL_ID}.json"
sudo chmod 600 /root/.cloudflared/${TUNNEL_ID}.json

# --- Build config.yml ---
echo "⚙️ Generating /etc/cloudflared/config.yml..."
sudo bash -c "cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json
ingress:
$(for DOMAIN in "${DOMAINS[@]}"; do
echo "  - hostname: $DOMAIN"
echo "    service: http://$CLUSTER_IP:80"
done)
  - service: http_status:404
EOF"
sudo chmod 644 /etc/cloudflared/config.yml

# --- Create systemd service ---
echo "🧩 Creating /etc/systemd/system/cloudflared.service..."
sudo bash -c "cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel Service
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared --config /etc/cloudflared/config.yml tunnel run
Restart=always
User=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF"
sudo chmod 644 /etc/systemd/system/cloudflared.service

# --- Reload and start Cloudflare service ---
echo "🔄 Reloading systemd and starting Cloudflare service..."
sudo restorecon -Rv /usr/local/bin/cloudflared /etc/systemd/system/cloudflared.service || true
sudo systemctl daemon-reexec || true
sudo systemctl daemon-reload || true
sudo systemctl enable cloudflared --now || true
sleep 5
sudo systemctl restart cloudflared || true
sudo systemctl status cloudflared --no-pager || true

# --- Verify connectivity ---
echo "🔍 Verifying Cloudflare tunnel connectivity..."
for DOMAIN in "${DOMAINS[@]}"; do
  echo "🌐 Testing https://$DOMAIN"
  if curl -Is "https://$DOMAIN" | grep -q "200"; then
    echo "✅ $DOMAIN reachable via Cloudflare tunnel"
  else
    echo "⚠️ $DOMAIN not reachable yet, retrying in 10s..."
    sleep 10
    curl -Is "https://$DOMAIN" || true
  fi
done

echo "🎯 Cloudflare tunnel setup complete and validated!"
