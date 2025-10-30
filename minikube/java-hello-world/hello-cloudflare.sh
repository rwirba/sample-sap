# #!/bin/bash
# set -euo pipefail

# APP_NAME="hello"
# NAMESPACE="demo"
# DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
# HOSTNAME="${APP_NAME}.${DOMAIN}"
# CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
# SERVICE_NAME="cloudflared-${APP_NAME}.service"
# TUNNEL_S3="s3://ryandevlab-bucket/cloudflare-tunnels/${APP_NAME}-tunnel.json"
# CRED_FILE="/home/ec2-user/.cloudflared/${APP_NAME}.json"
# CONFIG_FILE="${CONFIG_DIR}/config.yml"

# echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# # --- Download tunnel credentials from S3 ---
# echo "📥 Downloading tunnel credentials..."
# aws s3 cp "${TUNNEL_S3}" "${CRED_FILE}" --quiet
# if [[ ! -f "$CRED_FILE" ]]; then
#   echo "❌ Failed to download tunnel credentials from S3."
#   exit 1
# fi

# TUNNEL_ID=$(jq -r .TunnelID "${CRED_FILE}")

# # --- Ensure service is NodePort ---
# if ! kubectl get svc java-${APP_NAME}-world -n "${NAMESPACE}" &>/dev/null; then
#   echo "❌ Service java-${APP_NAME}-world not found in namespace ${NAMESPACE}"
#   exit 1
# fi

# SERVICE_TYPE=$(kubectl get svc java-${APP_NAME}-world -n "${NAMESPACE}" -o jsonpath='{.spec.type}')
# if [[ "${SERVICE_TYPE}" != "NodePort" ]]; then
#   echo "🔧 Patching service java-${APP_NAME}-world to NodePort..."
#   kubectl patch svc java-${APP_NAME}-world -n "${NAMESPACE}" -p '{"spec": {"type": "NodePort"}}' >/dev/null
#   sleep 4
# fi

# # --- Extract Minikube IP and NodePort ---
# MINIKUBE_IP=$(minikube ip)
# NODE_PORT=$(kubectl get svc java-${APP_NAME}-world -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')

# if [[ -z "$NODE_PORT" ]]; then
#   echo "❌ Failed to obtain NodePort from service."
#   exit 1
# fi

# echo "🌐 Minikube IP: ${MINIKUBE_IP}"
# echo "🔢 NodePort: ${NODE_PORT}"

# # --- Write Cloudflare config ---
# sudo mkdir -p "${CONFIG_DIR}"

# # Dynamically detect target port inside the Kubernetes service
# TARGET_PORT=$(kubectl get svc java-${APP_NAME}-world -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].targetPort}')

# sudo bash -c "cat > ${CONFIG_FILE}" <<EOF
# tunnel: ${TUNNEL_ID}
# credentials-file: ${CRED_FILE}
# ingress:
#   - hostname: ${HOSTNAME}
#     service: http://${MINIKUBE_IP}:${NODE_PORT}
#     originRequest:
#       httpHostHeader: java-${APP_NAME}-world
#       noTLSVerify: true
#   - service: http_status:404
# EOF



# # --- Create systemd unit ---
# sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME}" <<EOF
# [Unit]
# Description=Cloudflare Tunnel - ${APP_NAME}
# After=network.target

# [Service]
# ExecStart=/usr/local/bin/cloudflared --config ${CONFIG_FILE} tunnel run
# Restart=always
# User=ec2-user
# Environment=HOME=/home/ec2-user

# [Install]
# WantedBy=multi-user.target
# EOF

# # --- Restart cloudflared service ---
# sudo systemctl daemon-reload
# sudo systemctl enable "${SERVICE_NAME}" --now
# sudo systemctl restart "${SERVICE_NAME}"

# sleep 5
# sudo systemctl status "${SERVICE_NAME}" --no-pager || true

# if ! cloudflared tunnel route dns ${APP_NAME}-tunnel ${HOSTNAME} 2>&1 | grep -q "already exists"; then
#   echo "✅ DNS record created for ${HOSTNAME}"
# else
#   echo "ℹ️ DNS record already exists for ${HOSTNAME}, skipping..."
# fi



# echo "✅ ${APP_NAME} app now accessible at: https://${HOSTNAME}"


#!/bin/bash
set -euo pipefail

# ==========================
# CONFIGURATION
# ==========================
APP_NAME="hello"
NAMESPACE="demo"
DOMAIN_FILE="/etc/minikube/env-info.json"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
S3_BUCKET="ryandevlab-bucket"
TUNNEL_S3="s3://${S3_BUCKET}/cloudflare-tunnels/${APP_NAME}-tunnel.json"
CRED_FILE="/home/ec2-user/.cloudflared/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"

# ==========================
# VALIDATION
# ==========================
if [[ ! -f "$DOMAIN_FILE" ]]; then
  echo "❌ ${DOMAIN_FILE} not found. Please ensure Minikube env-info.json exists."
  exit 1
fi

DOMAIN=$(jq -r .domain "$DOMAIN_FILE")
HOSTNAME="${APP_NAME}.${DOMAIN}"
SVC_NAME="java-${APP_NAME}-world"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."

# ==========================
# DOWNLOAD CREDENTIALS
# ==========================
echo "📥 Downloading tunnel credentials from S3..."
sudo mkdir -p "$(dirname "$CRED_FILE")" "$CONFIG_DIR"
aws s3 cp "${TUNNEL_S3}" "${CRED_FILE}" --quiet

if [[ ! -f "$CRED_FILE" ]]; then
  echo "❌ Failed to download tunnel credentials from ${TUNNEL_S3}"
  exit 1
fi

TUNNEL_ID=$(jq -r .TunnelID "${CRED_FILE}")

# ==========================
# VERIFY & PATCH SERVICE
# ==========================
if ! kubectl get svc "${SVC_NAME}" -n "${NAMESPACE}" &>/dev/null; then
  echo "❌ Service ${SVC_NAME} not found in namespace ${NAMESPACE}"
  exit 1
fi

SERVICE_TYPE=$(kubectl get svc "${SVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}')
if [[ "${SERVICE_TYPE}" != "NodePort" ]]; then
  echo "🔧 Patching service ${SVC_NAME} to NodePort..."
  kubectl patch svc "${SVC_NAME}" -n "${NAMESPACE}" -p '{"spec": {"type": "NodePort"}}' >/dev/null
  sleep 3
fi

# ==========================
# DETECT NETWORK INFO
# ==========================
MINIKUBE_IP=$(minikube ip)
NODE_PORT=$(kubectl get svc "${SVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')
TARGET_PORT=$(kubectl get svc "${SVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].targetPort}')

if [[ -z "$NODE_PORT" || -z "$TARGET_PORT" ]]; then
  echo "❌ Failed to detect NodePort or TargetPort."
  exit 1
fi

echo "🌐 Minikube IP: ${MINIKUBE_IP}"
echo "🔢 NodePort: ${NODE_PORT}"
echo "🎯 TargetPort: ${TARGET_PORT}"

# ==========================
# BUILD CLOUDFLARE CONFIG
# ==========================
sudo bash -c "cat > ${CONFIG_FILE}" <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}
ingress:
  - hostname: ${HOSTNAME}
    service: http://${MINIKUBE_IP}:${NODE_PORT}
    originRequest:
      httpHostHeader: ${SVC_NAME}.${NAMESPACE}.svc.cluster.local
      noTLSVerify: true
      connectTimeout: 10s
      keepAliveTimeout: 30s
  - service: http_status:404
EOF

echo "🧾 Cloudflare config written to ${CONFIG_FILE}"

# ==========================
# CREATE SYSTEMD SERVICE
# ==========================
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

# ==========================
# ENABLE & START SERVICE
# ==========================
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sudo systemctl restart "${SERVICE_NAME}"
sleep 5

sudo systemctl status "${SERVICE_NAME}" --no-pager || true

# ==========================
# VALIDATE DNS ROUTE
# ==========================
if ! cloudflared tunnel route dns "${APP_NAME}-tunnel" "${HOSTNAME}" 2>&1 | grep -q "already exists"; then
  echo "✅ DNS record created for ${HOSTNAME}"
else
  echo "ℹ️ DNS record already exists for ${HOSTNAME}, skipping..."
fi

echo "✅ ${APP_NAME} app now accessible at: https://${HOSTNAME}"

