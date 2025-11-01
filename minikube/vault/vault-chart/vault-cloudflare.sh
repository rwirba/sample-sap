#!/bin/bash
set -euo pipefail

APP_NAME="vault"
NAMESPACE="vault"
SERVICE="vault-demo"
DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
HOSTNAME="${APP_NAME}.${DOMAIN}"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
TUNNEL_S3="s3://ryandevlab-bucket/cloudflare-tunnels/${APP_NAME}-tunnel.json"
CRED_FILE="/home/ec2-user/.cloudflared/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# --- Download tunnel credentials
echo "📥 Downloading tunnel credentials..."
aws s3 cp "${TUNNEL_S3}" "${CRED_FILE}" --quiet
[[ -f "${CRED_FILE}" ]] || { echo "❌ Failed to download tunnel credentials from S3."; exit 1; }

TUNNEL_ID=$(jq -r .TunnelID "${CRED_FILE}")

# --- Ensure service exists
if ! kubectl get svc "${SERVICE}" -n "${NAMESPACE}" &>/dev/null; then
  echo "❌ Service ${SERVICE} not found in namespace ${NAMESPACE}"
  exit 1
fi

# --- Ensure service type is NodePort
SERVICE_TYPE=$(kubectl get svc "${SERVICE}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}')
if [[ "${SERVICE_TYPE}" != "NodePort" ]]; then
  echo "🔧 Patching service ${SERVICE} to NodePort..."
  kubectl patch svc "${SERVICE}" -n "${NAMESPACE}" -p '{"spec": {"type": "NodePort"}}' >/dev/null
  sleep 4
fi

# --- Get NodePort and test local reachability
MINIKUBE_IP=$(minikube ip)
NODE_PORT=$(kubectl get svc "${SERVICE}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')

echo "🌐 Minikube IP: ${MINIKUBE_IP}"
echo "🔢 NodePort: ${NODE_PORT}"

if curl -s --max-time 5 "http://${MINIKUBE_IP}:${NODE_PORT}/ui" >/dev/null; then
  echo "✅ Local connection test passed."
else
  echo "⚠️ Vault dev UI may still be initializing."
fi

# --- Write Cloudflare config
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

# --- Configure systemd tunnel service
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

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sudo systemctl restart "${SERVICE_NAME}"
sleep 5
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

cloudflared tunnel route dns "${APP_NAME}-tunnel" "${HOSTNAME}" || true

echo "✅ Vault now accessible at: https://${HOSTNAME}"
