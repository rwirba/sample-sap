#!/bin/bash
set -euo pipefail

APP_NAME="ads"
NAMESPACE="demo"
DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
HOSTNAME="${APP_NAME}.${DOMAIN}"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
TUNNEL_S3="s3://ryandevlab-bucket/cloudflare-tunnels/${APP_NAME}-tunnel.json"
CRED_FILE="/home/ec2-user/.cloudflared/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# --- Fetch tunnel credentials from S3 ---
echo "📥 Downloading tunnel credentials..."
aws s3 cp "${TUNNEL_S3}" "${CRED_FILE}" --quiet
if [[ ! -f "$CRED_FILE" ]]; then
  echo "❌ Failed to download tunnel credentials from S3. Exiting."
  exit 1
fi

TUNNEL_ID=$(jq -r .TunnelID "${CRED_FILE}")

# --- Get Minikube IP and NodePort ---
MINIKUBE_IP=$(minikube ip)
NODE_PORT=$(kubectl get svc java-ads-demo -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')

echo "🌐 Minikube IP: ${MINIKUBE_IP}"
echo "🔢 NodePort: ${NODE_PORT}"

# --- Write Cloudflare config ---
sudo mkdir -p "${CONFIG_DIR}"
sudo bash -c "cat > ${CONFIG_FILE}" <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}
ingress:
  - hostname: ${HOSTNAME}
    service: http://${MINIKUBE_IP}:${NODE_PORT}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

# --- Create systemd service ---
sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME}" <<EOF
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
EOF

# --- Restart service ---
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME} --now
sudo systemctl restart ${SERVICE_NAME}

sleep 5
sudo systemctl status ${SERVICE_NAME} --no-pager

# --- Verify tunnel health ---
cloudflared tunnel info ${APP_NAME}-tunnel || true

echo "✅ ${APP_NAME} app available at: https://${HOSTNAME}"
