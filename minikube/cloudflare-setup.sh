#!/bin/bash
set -euo pipefail

S3_TUNNEL_PATH="s3://ryandevlab-bucket/cloudflare-tunnel.json"
TUNNEL_NAME="minikube-tunnel"
ZONE="mitechnology.org"
DOMAINS=("hello.mitechnology.org" "ads.mitechnology.org")

echo "🚀 Setting up Cloudflare Tunnel..."
sudo dnf install -y awscli jq

# load cluster info
if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Cluster info file not found. Run setup.sh first!"
  exit 1
fi

NAMESPACE=$(jq -r .namespace /etc/minikube/env-info.json)
CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)
echo "🌐 Namespace: $NAMESPACE | Cluster IP: $CLUSTER_IP"

# install cloudflared
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

# download tunnel creds from S3
echo "📥 Downloading Cloudflare tunnel credentials from S3..."
sudo mkdir -p /root/.cloudflared /etc/cloudflared

# Download the JSON as root
sudo aws s3 cp "$S3_TUNNEL_PATH" /root/.cloudflared/tunnel.json --quiet

# Extract tunnel ID
TUNNEL_ID=$(sudo jq -r .TunnelID /root/.cloudflared/tunnel.json)
echo "📘 Tunnel ID: $TUNNEL_ID"

# Copy credentials for config reference
sudo cp /root/.cloudflared/tunnel.json "/root/.cloudflared/${TUNNEL_ID}.json"
sudo chmod 600 /root/.cloudflared/${TUNNEL_ID}.json


# build config.yml safely with sudo
echo "⚙️ Generating /etc/cloudflared/config.yml..."
sudo bash -c "cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json
ingress:
$(for DOMAIN in "${DOMAINS[@]}"; do
echo "  - hostname: $DOMAIN"
echo "    service: https://$CLUSTER_IP:443"
done)
  - service: http_status:404
EOF"
sudo chmod 644 /etc/cloudflared/config.yml


# systemd
cat >/etc/systemd/system/cloudflared.service <<EOF
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
EOF

restorecon -Rv /usr/local/bin/cloudflared /etc/systemd/system/cloudflared.service || true
systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared
sleep 3
systemctl status cloudflared --no-pager || true
#
# verify tunnel
cloudflared tunnel info "$TUNNEL_NAME" || true

echo "✅ Cloudflare tunnel setup complete!"
