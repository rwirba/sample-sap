#!/bin/bash
set -euo pipefail

APP_NAME="dashboard"
HOSTNAME="${APP_NAME}.ryandemolab.app"
TUNNEL_ID="0e5c75e7-4566-44a9-b988-7a79c9f5e11a"
CRED_FILE="/home/ec2-user/.cloudflared/${TUNNEL_ID}.json"
CONFIG_FILE="/etc/cloudflared/${APP_NAME}/config.yml"
SERVICE_NAME="cloudflared-${APP_NAME}.service"

echo "🚀 Launching Kubernetes Dashboard and syncing Cloudflare tunnel..."

# 1️⃣ Start (or restart) dashboard proxy and capture its URL
echo "⏳ Starting dashboard..."
nohup minikube dashboard --url > /tmp/minikube-dashboard-url.txt 2>&1 &
sleep 8
URL=$(grep -Eo 'http://127\.0\.0\.1:[0-9]+/api/v1/.*proxy/' /tmp/minikube-dashboard-url.txt | head -n1)
if [[ -z "$URL" ]]; then
  echo "❌ Could not detect dashboard URL."
  exit 1
fi
echo "🌐 Dashboard local URL: $URL"

# 2️⃣ Parse port from URL
PORT=$(echo "$URL" | grep -Eo '[0-9]+' | head -n1)
echo "📘 Detected dashboard port: $PORT"

# 3️⃣ Write fresh Cloudflare config
sudo mkdir -p "$(dirname "$CONFIG_FILE")"
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

echo "🧩 Updated Cloudflare config at ${CONFIG_FILE}"

# 4️⃣ Restart cloudflared
sudo systemctl daemon-reload
sudo systemctl restart ${SERVICE_NAME}
sleep 3
sudo systemctl status ${SERVICE_NAME} --no-pager || true

echo "✅ Tunnel updated successfully."
echo "🌍 Visit https://${HOSTNAME}"
