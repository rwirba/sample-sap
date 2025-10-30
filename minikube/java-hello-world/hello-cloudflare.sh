# #!/bin/bash
# set -euo pipefail

# # ========== CONFIGURATION ==========
# APP_NAME="hello"
# HOSTNAME="${APP_NAME}.ryandemolab.app"
# S3_TUNNEL_PATH="s3://ryandevlab-bucket/cloudflare-tunnel.json"
# TUNNEL_DIR="/etc/cloudflared/${APP_NAME}"
# SERVICE_NAME="cloudflared-${APP_NAME}.service"

# # --- Ensure cloudflared binary exists ---
# if ! command -v cloudflared &>/dev/null; then
#   ARCH=$(uname -m)
#   [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
#   echo "Installing Cloudflared..."
#   sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
#        -o /usr/local/bin/cloudflared
#   sudo chmod +x /usr/local/bin/cloudflared
# fi


# echo "Setting up Cloudflare Tunnel for ${APP_NAME}..."

# # ========== DETECT USER & CERT LOCATIONS ==========
# USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6 2>/dev/null || echo "$HOME")
# USER_CERT_PATH="${USER_HOME}/.cloudflared/cert.pem"
# ROOT_CERT_PATH="/root/.cloudflared/cert.pem"

# echo "Checking Cloudflare cert.pem..."

# # --- Case 1: cert exists only under user home
# if [[ -f "$USER_CERT_PATH" && ! -f "$ROOT_CERT_PATH" ]]; then
#   echo "Copying Cloudflare cert from $USER_CERT_PATH to /root/.cloudflared..."
#   sudo mkdir -p /root/.cloudflared
#   sudo cp "$USER_CERT_PATH" "$ROOT_CERT_PATH"
#   sudo chmod 600 "$ROOT_CERT_PATH"
#   sudo chown root:root "$ROOT_CERT_PATH"
#   echo "Cert copied to /root/.cloudflared"
# fi

# # --- Case 2: cert missing entirely
# if [[ ! -f "$USER_CERT_PATH" && ! -f "$ROOT_CERT_PATH" ]]; then
#   echo "Cloudflare login certificate missing!"
#   echo "Run the following, then rerun this script:"
#   echo ""
#   echo "   cloudflared login"
#   echo ""
#   echo "After that, it will appear at ~/.cloudflared/cert.pem automatically."
#   exit 1
# fi

# # --- Always prefer whichever exists
# if [[ -f "$ROOT_CERT_PATH" ]]; then
#   export TUNNEL_ORIGIN_CERT="$ROOT_CERT_PATH"
# else
#   export TUNNEL_ORIGIN_CERT="$USER_CERT_PATH"
# fi

# echo "Using cert at $TUNNEL_ORIGIN_CERT"

# # ========== INSTALL DEPENDENCIES ==========
# sudo dnf install -y awscli jq curl policycoreutils || true

# # ========== LOAD CLUSTER INFO ==========
# if [[ ! -f /etc/minikube/env-info.json ]]; then
#   echo "Missing /etc/minikube/env-info.json. Run global-setup.sh first."
#   exit 1
# fi
# CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)
# echo "🌐 Using Minikube IP: ${CLUSTER_IP}"

# # ========== FETCH TUNNEL CREDS ==========
# sudo mkdir -p "$TUNNEL_DIR"
# sudo aws s3 cp "$S3_TUNNEL_PATH" "$TUNNEL_DIR/tunnel.json" --quiet
# TUNNEL_ID=$(sudo jq -r .TunnelID "$TUNNEL_DIR/tunnel.json")
# sudo cp "$TUNNEL_DIR/tunnel.json" "/root/.cloudflared/${TUNNEL_ID}.json"

# # ========== GENERATE CONFIG ==========
# echo "Generating ${TUNNEL_DIR}/config.yml..."
# sudo bash -c "cat > ${TUNNEL_DIR}/config.yml <<EOF
# tunnel: ${TUNNEL_ID}
# credentials-file: /root/.cloudflared/${TUNNEL_ID}.json
# ingress:
#   - hostname: ${HOSTNAME}
#     service: http://${CLUSTER_IP}:80
#   - service: http_status:404
# EOF"
# sudo chmod 644 "${TUNNEL_DIR}/config.yml"

# # ========== CREATE SYSTEMD SERVICE ==========
# echo "Creating ${SERVICE_NAME}..."
# sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME} <<EOF
# [Unit]
# Description=Cloudflare Tunnel - ${APP_NAME}
# After=network.target

# [Service]
# ExecStart=/usr/local/bin/cloudflared --config ${TUNNEL_DIR}/config.yml tunnel run
# Restart=always
# User=root
# Environment=HOME=/root
# Environment=TUNNEL_ORIGIN_CERT=$TUNNEL_ORIGIN_CERT

# [Install]
# WantedBy=multi-user.target
# EOF"

# # ========== ENABLE & START SERVICE ==========
# sudo systemctl daemon-reload
# sudo systemctl enable "${SERVICE_NAME}" --now
# sleep 5
# sudo systemctl status "${SERVICE_NAME}" --no-pager || true

# echo "Tunnel for ${APP_NAME} ready at https://${HOSTNAME}"

# # ========== DNS REGISTRATION ==========
# echo "Checking DNS route for ${HOSTNAME}..."
# if cloudflared tunnel route dns list 2>/dev/null | grep -q "${HOSTNAME}"; then
#   echo "DNS route for ${HOSTNAME} already exists."
# else
#   echo "Registering new DNS route for ${HOSTNAME}..."
#   cloudflared tunnel route dns "${TUNNEL_ID}" "${HOSTNAME}" && \
#   echo "DNS route created for ${HOSTNAME}."
# fi


#!/bin/bash
set -euo pipefail

APP_NAME="hello"
DOMAIN=$(jq -r .domain /etc/minikube/env-info.json)
HOSTNAME="${APP_NAME}.${DOMAIN}"
CONFIG_DIR="/etc/cloudflared/${APP_NAME}"
SERVICE_NAME="cloudflared-${APP_NAME}.service"
TUNNEL_JSON=$(jq -r .tunnels.hello /etc/minikube/env-info.json)
CRED_FILE="/home/ec2-user/.cloudflared/${APP_NAME}.json"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
INGRESS_FILE="/opt/minikube/hello-ingress.yml"

echo "🚀 Setting up Cloudflare Tunnel for ${HOSTNAME}..."
sudo mkdir -p ~/.cloudflared "$CONFIG_DIR"

aws s3 cp "$TUNNEL_JSON" "$CRED_FILE"

TUNNEL_ID=$(jq -r .TunnelID "$CRED_FILE")
CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)


sudo bash -c "cat > ${CONFIG_FILE} <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}
ingress:
  - hostname: ${HOSTNAME}
    service: http://${CLUSTER_IP}:81
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF"

sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME} <<EOF
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
EOF"

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}" --now
sleep 3
cloudflared tunnel route dns "$TUNNEL_ID" "$HOSTNAME" || true

echo "✅ hello app available at: https://${HOSTNAME}"
