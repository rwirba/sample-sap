# #!/bin/bash
# set -euo pipefail

# # ========= GLOBAL CONFIG =========
# DOMAIN="ryandemolab.app"
# S3_BUCKET="ryandevlab-bucket"
# S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
# S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
# S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
# SECRET_NAME="cloudflare-cert"
# NAMESPACE="demo"
# LOCAL_CF_DIR="/home/ec2-user/.cloudflared"

# echo "🌍 Setting up global environment for Minikube + Cloudflare (${DOMAIN})..."

# # ========= INSTALL DEPENDENCIES =========
# sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

# # --- Cloudflared ---
# if ! command -v cloudflared &>/dev/null; then
#   ARCH=$(uname -m)
#   [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
#   echo "📦 Installing Cloudflared..."
#   sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
#        -o /usr/local/bin/cloudflared
#   sudo chmod +x /usr/local/bin/cloudflared
# fi

# # --- Passwordless sudo ---
# if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
#   echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user >/dev/null
#   sudo chmod 440 /etc/sudoers.d/ec2-user
#   echo "✅ ec2-user granted passwordless sudo"
# fi

# # ========= INSTALL MINIKUBE / HELM / KUBECTL =========
# if ! command -v kubectl &>/dev/null; then
#   echo "📦 Installing kubectl..."
#   curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#   chmod +x kubectl && sudo mv kubectl /usr/local/bin/
# fi

# if ! command -v minikube &>/dev/null; then
#   echo "📦 Installing Minikube..."
#   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
#   chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
# fi

# if ! command -v helm &>/dev/null; then
#   echo "📦 Installing Helm..."
#   curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
#   tar -zxf helm-v3.13.1-linux-amd64.tar.gz >/dev/null
#   sudo mv linux-amd64/helm /usr/local/bin/helm
#   rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
# fi

# # # ========= START MINIKUBE =========
# # if ! minikube status | grep -q "Running"; then
# #   echo "🚀 Starting Minikube (Podman driver)..."
# #   minikube start --driver=podman --force
# # else
# #   echo "✅ Minikube already running."
# # fi

# # kubectl wait --for=condition=Ready node --all --timeout=180s || true

# # ========= START MINIKUBE =========
# MIN_CPUS=4
# MIN_MEM=16384   # 16GB in MB

# if ! minikube status | grep -q "Running"; then
#   echo "🚀 Starting Minikube (Podman driver) with recommended resources..."
#   minikube start --driver=podman --cpus=6 --memory=24576 --disk-size=80g --force
# else
#   echo "✅ Minikube already running. Checking resources..."
#   CPUS=$(minikube ssh -- "nproc" 2>/dev/null || echo 0)
#   MEM_MB=$(minikube ssh -- "free -m | awk '/Mem:/ {print \$2}'" 2>/dev/null || echo 0)

#   if (( CPUS < MIN_CPUS )) || (( MEM_MB < MIN_MEM )); then
#     echo "⚠️  Current Minikube node resources too low for SAP HANA:"
#     echo "   → CPUs: ${CPUS} (min ${MIN_CPUS})"
#     echo "   → Memory: ${MEM_MB}MB (min ${MIN_MEM}MB)"
#     echo "💡 Recreating Minikube with optimal settings..."
#     read -p "Recreate Minikube now? (y/n): " CONFIRM
#     if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
#       minikube delete
#       minikube start --driver=podman --cpus=6 --memory=24576 --disk-size=80g --force
#     else
#       echo "⚠️  Continuing with limited resources..."
#     fi
#   else
#     echo "✅ Minikube meets HANA resource requirements (${CPUS} CPUs, ${MEM_MB}MB RAM)."
#   fi
# fi

# # Wait for all nodes to be ready
# kubectl wait --for=condition=Ready node --all --timeout=180s || true


# # ========= ENABLE INGRESS =========
# if ! kubectl get ns ingress-nginx &>/dev/null; then
#   echo "🧩 Enabling ingress controller..."
#   minikube addons enable ingress
# fi
# kubectl wait -n ingress-nginx \
#   --for=condition=Ready pod \
#   -l app.kubernetes.io/component=controller \
#   --timeout=180s || true

# # ========= TLS SECRET =========
# TMPDIR=$(mktemp -d)
# aws s3 cp "$S3_CERT_PATH" "$TMPDIR/origin.crt" --quiet || true
# aws s3 cp "$S3_KEY_PATH" "$TMPDIR/origin.key" --quiet || true

# if [[ -f "$TMPDIR/origin.crt" && -f "$TMPDIR/origin.key" ]]; then
#   kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
#   kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
#   kubectl create secret tls "$SECRET_NAME" \
#     --cert="$TMPDIR/origin.crt" \
#     --key="$TMPDIR/origin.key" \
#     -n "$NAMESPACE"
#   echo "✅ TLS secret created in namespace '$NAMESPACE'"
# else
#   echo "⚠️ TLS certificate files not found in S3. Skipping."
# fi
# rm -rf "$TMPDIR"

# # ========= CLOUDFLARE TUNNELS =========
# echo "🧭 Checking Cloudflare tunnels..."
# sudo mkdir -p "$LOCAL_CF_DIR"
# sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

# if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
#   echo "❌ Cloudflare not authenticated. Run 'cloudflared login' first."
#   exit 1
# fi

# APPS=("dashboard" "hello" "ads")
# for APP in "${APPS[@]}"; do
#   JSON_FILE="${LOCAL_CF_DIR}/${APP}-tunnel.json"
#   S3_FILE="${S3_TUNNEL_PATH}/${APP}-tunnel.json"

#   echo "🔹 Processing tunnel for ${APP}..."

#   if aws s3 ls "${S3_FILE}" >/dev/null 2>&1; then
#     echo "✅ Found in S3. Downloading..."
#     aws s3 cp "${S3_FILE}" "${JSON_FILE}" --quiet
#   elif cloudflared tunnel list 2>/dev/null | grep -q "${APP}-tunnel"; then
#     echo "✅ Tunnel exists in Cloudflare. Exporting credentials..."
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   else
#     echo "🌐 Creating new tunnel: ${APP}-tunnel"
#     cloudflared tunnel create "${APP}-tunnel"
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   fi

#   sudo chown ec2-user:ec2-user "${JSON_FILE}"
#   sudo chmod 600 "${JSON_FILE}"

#   echo "⬆️ Uploading ${APP}-tunnel.json to S3..."
#   aws s3 cp "${JSON_FILE}" "${S3_FILE}" --quiet
# done

# # ========= RECORD ENVIRONMENT =========
# CLUSTER_IP=$(minikube ip)
# sudo mkdir -p /etc/minikube

# cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
# {
#   "namespace": "$NAMESPACE",
#   "cluster_ip": "$CLUSTER_IP",
#   "domain": "$DOMAIN",
#   "tunnels": {
#     "dashboard": "${S3_TUNNEL_PATH}/dashboard-tunnel.json",
#     "hello": "${S3_TUNNEL_PATH}/hello-tunnel.json",
#     "ads": "${S3_TUNNEL_PATH}/ads-tunnel.json"
#   }
# }
# EOF

# echo "💾 Environment info saved:"
# cat /etc/minikube/env-info.json

# echo "🎯 Global setup complete with Cloudflare tunnels synchronized to S3."

# #!/bin/bash
# set -euo pipefail

# # ========= GLOBAL CONFIG =========
# DOMAIN="ryandemolab.app"
# S3_BUCKET="ryandevlab-bucket"
# S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
# S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
# S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
# SECRET_NAME="cloudflare-cert"
# NAMESPACE="demo"
# LOCAL_CF_DIR="/home/ec2-user/.cloudflared"

# echo "🌍 Setting up global environment for Minikube + Cloudflare (${DOMAIN})..."

# # ========= INSTALL DEPENDENCIES =========
# sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

# # --- Cloudflared ---
# if ! command -v cloudflared &>/dev/null; then
#   ARCH=$(uname -m)
#   [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
#   echo "📦 Installing Cloudflared..."
#   sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
#        -o /usr/local/bin/cloudflared
#   sudo chmod +x /usr/local/bin/cloudflared
# fi

# # --- Passwordless sudo ---
# if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
#   echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user >/dev/null
#   sudo chmod 440 /etc/sudoers.d/ec2-user
#   echo "✅ ec2-user granted passwordless sudo"
# fi

# # ========= INSTALL MINIKUBE / HELM / KUBECTL =========
# if ! command -v kubectl &>/dev/null; then
#   echo "📦 Installing kubectl..."
#   curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#   chmod +x kubectl && sudo mv kubectl /usr/local/bin/
# fi

# if ! command -v minikube &>/dev/null; then
#   echo "📦 Installing Minikube..."
#   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
#   chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
# fi

# if ! command -v helm &>/dev/null; then
#   echo "📦 Installing Helm..."
#   curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
#   tar -zxf helm-v3.13.1-linux-amd64.tar.gz >/dev/null
#   sudo mv linux-amd64/helm /usr/local/bin/helm
#   rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
# fi

# # # ========= START MINIKUBE =========
# # if ! minikube status | grep -q "Running"; then
# #   echo "🚀 Starting Minikube (Podman driver)..."
# #   minikube start --driver=podman --force
# # else
# #   echo "✅ Minikube already running."
# # fi

# # kubectl wait --for=condition=Ready node --all --timeout=180s || true

# # ========= START MINIKUBE =========
# echo "🚀 Checking system capacity before starting Minikube..."

# # Detect available host resources
# HOST_CPUS=$(nproc)
# HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')  # MB

# # Recommend: 4 CPUs, 16GB (16384MB) minimum; reserve ~2GB for OS
# REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
# REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

# echo "🧠 Host: ${HOST_CPUS} CPUs, ${HOST_MEM}MB RAM"
# echo "⚙️  Using Minikube config → CPUs=${REQ_CPUS}, Memory=${REQ_MEM}MB"

# if ! minikube status | grep -q "Running"; then
#   echo "🚀 Starting Minikube (Podman driver) with adjusted resources..."
#   minikube start --driver=podman --cpus="${REQ_CPUS}" --memory="${REQ_MEM}" --disk-size=50g --force
# else
#   echo "✅ Minikube already running. Verifying resource levels..."
#   minikube ssh -- "nproc; free -h"
# fi

# # Wait for nodes to become ready
# kubectl wait --for=condition=Ready node --all --timeout=180s || true


# # ---- Kernel parameters recommended for HANA ----
# echo "[INFO] Applying kernel parameters for SAP HANA..."
# sudo tee /etc/sysctl.d/99-hana.conf >/dev/null <<'EOF'
# fs.file-max=20000000
# fs.aio-max-nr=262144
# vm.memory_failure_early_kill=1
# vm.max_map_count=135217728
# net.ipv4.ip_local_port_range=40000 60999
# EOF

# sudo sysctl --system


# # ---- Create persistent storage path ----
# sudo mkdir -p /data/hxe /opt/hana /opt/scripts
# sudo chmod -R 777 /data /opt
# # Wait for all nodes to be ready
# kubectl wait --for=condition=Ready node --all --timeout=180s || true


# # ========= ENABLE INGRESS =========
# if ! kubectl get ns ingress-nginx &>/dev/null; then
#   echo "🧩 Enabling ingress controller..."
#   minikube addons enable ingress
# fi
# kubectl wait -n ingress-nginx \
#   --for=condition=Ready pod \
#   -l app.kubernetes.io/component=controller \
#   --timeout=180s || true

# # ========= TLS SECRET =========
# TMPDIR=$(mktemp -d)
# aws s3 cp "$S3_CERT_PATH" "$TMPDIR/origin.crt" --quiet || true
# aws s3 cp "$S3_KEY_PATH" "$TMPDIR/origin.key" --quiet || true

# if [[ -f "$TMPDIR/origin.crt" && -f "$TMPDIR/origin.key" ]]; then
#   kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
#   kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
#   kubectl create secret tls "$SECRET_NAME" \
#     --cert="$TMPDIR/origin.crt" \
#     --key="$TMPDIR/origin.key" \
#     -n "$NAMESPACE"
#   echo "✅ TLS secret created in namespace '$NAMESPACE'"
# else
#   echo "⚠️ TLS certificate files not found in S3. Skipping."
# fi
# rm -rf "$TMPDIR"

# # ========= CLOUDFLARE TUNNELS =========
# echo "🧭 Checking Cloudflare tunnels..."
# sudo mkdir -p "$LOCAL_CF_DIR"
# sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

# if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
#   echo "❌ Cloudflare not authenticated. Run 'cloudflared login' first."
#   exit 1
# fi

# APPS=("dashboard" "hello" "ads")
# for APP in "${APPS[@]}"; do
#   JSON_FILE="${LOCAL_CF_DIR}/${APP}-tunnel.json"
#   S3_FILE="${S3_TUNNEL_PATH}/${APP}-tunnel.json"

#   echo "🔹 Processing tunnel for ${APP}..."

#   if aws s3 ls "${S3_FILE}" >/dev/null 2>&1; then
#     echo "✅ Found in S3. Downloading..."
#     aws s3 cp "${S3_FILE}" "${JSON_FILE}" --quiet
#   elif cloudflared tunnel list 2>/dev/null | grep -q "${APP}-tunnel"; then
#     echo "✅ Tunnel exists in Cloudflare. Exporting credentials..."
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   else
#     echo "🌐 Creating new tunnel: ${APP}-tunnel"
#     cloudflared tunnel create "${APP}-tunnel"
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   fi

#   sudo chown ec2-user:ec2-user "${JSON_FILE}"
#   sudo chmod 600 "${JSON_FILE}"

#   echo "⬆️ Uploading ${APP}-tunnel.json to S3..."
#   aws s3 cp "${JSON_FILE}" "${S3_FILE}" --quiet
# done

# # ========= RECORD ENVIRONMENT =========
# CLUSTER_IP=$(minikube ip)
# sudo mkdir -p /etc/minikube

# cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
# {
#   "namespace": "$NAMESPACE",
#   "cluster_ip": "$CLUSTER_IP",
#   "domain": "$DOMAIN",
#   "tunnels": {
#     "dashboard": "${S3_TUNNEL_PATH}/dashboard-tunnel.json",
#     "hello": "${S3_TUNNEL_PATH}/hello-tunnel.json",
#     "ads": "${S3_TUNNEL_PATH}/ads-tunnel.json"
#   }
# }
# EOF

# echo "💾 Environment info saved:"
# cat /etc/minikube/env-info.json

# echo "🎯 Global setup complete with Cloudflare tunnels synchronized to S3."


# #!/bin/bash
# set -euo pipefail

# # ========= GLOBAL CONFIG =========
# DOMAIN="ryandemolab.app"
# S3_BUCKET="ryandevlab-bucket"
# S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
# S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
# S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
# SECRET_NAME="cloudflare-cert"
# NAMESPACE="demo"
# LOCAL_CF_DIR="/home/ec2-user/.cloudflared"

# echo "🌍 Setting up global environment for Minikube + Cloudflare (${DOMAIN})..."

# # ========= INSTALL DEPENDENCIES =========
# sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

# # --- Cloudflared ---
# if ! command -v cloudflared &>/dev/null; then
#   ARCH=$(uname -m)
#   [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
#   echo "📦 Installing Cloudflared..."
#   sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
#        -o /usr/local/bin/cloudflared
#   sudo chmod +x /usr/local/bin/cloudflared
# fi

# # --- Passwordless sudo ---
# if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
#   echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user >/dev/null
#   sudo chmod 440 /etc/sudoers.d/ec2-user
#   echo "✅ ec2-user granted passwordless sudo"
# fi

# # ========= INSTALL MINIKUBE / HELM / KUBECTL =========
# if ! command -v kubectl &>/dev/null; then
#   echo "📦 Installing kubectl..."
#   curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#   chmod +x kubectl && sudo mv kubectl /usr/local/bin/
# fi

# if ! command -v minikube &>/dev/null; then
#   echo "📦 Installing Minikube..."
#   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
#   chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
# fi

# if ! command -v helm &>/dev/null; then
#   echo "📦 Installing Helm..."
#   curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
#   tar -zxf helm-v3.13.1-linux-amd64.tar.gz >/dev/null
#   sudo mv linux-amd64/helm /usr/local/bin/helm
#   rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
# fi

# # Detect available host resources
# HOST_CPUS=$(nproc)
# HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')  # MB

# # Recommend: 4 CPUs, 16GB (16384MB) minimum; reserve ~2GB for OS
# REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
# REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

# echo "Host: ${HOST_CPUS} CPUs, ${HOST_MEM}MB RAM"
# echo "Using Minikube config → CPUs=${REQ_CPUS}, Memory=${REQ_MEM}MB"

# # --- Persistent Minikube storage setup ---
# sudo mkdir -p /data/minikube
# sudo chown -R ec2-user:ec2-user /data/minikube
# echo "🗄️  Mounting /data/minikube for persistent cluster storage..."

# echo "🧹 Cleaning up old Minikube volumes..."
# minikube delete --all --purge || true
# sudo podman volume rm minikube || true

# if ! minikube status | grep -q "Running"; then
#   echo "🚀 Starting Minikube (Podman driver) with persistent storage..."
#   minikube start \
#     --driver=podman \
#     --mount=true \
#     --mount-string="/data/minikube:/var/lib/minikube" \
#     --cpus="${REQ_CPUS}" \
#     --memory="${REQ_MEM}" \
#     --disk-size=50g \
#     --force
# else
#   echo "✅ Minikube already running."
# fi

# # --- Create systemd autostart service for Minikube ---
# echo "⚙️  Configuring Minikube autostart systemd service..."
# sudo tee /etc/systemd/system/minikube-autostart.service >/dev/null <<EOF
# [Unit]
# Description=Auto-start Minikube on EC2 boot
# After=network-online.target
# Wants=network-online.target

# [Service]
# Type=oneshot
# ExecStart=/usr/local/bin/minikube start --driver=podman --mount=true --mount-string="/data/minikube:/var/lib/minikube" --force
# RemainAfterExit=yes
# User=ec2-user

# [Install]
# WantedBy=multi-user.target
# EOF

# sudo systemctl daemon-reload
# sudo systemctl enable minikube-autostart.service
# echo "✅ Minikube will now auto-start on EC2 reboot."

# # Wait for Minikube nodes to be ready
# kubectl wait --for=condition=Ready node --all --timeout=180s || true

# # ---- Kernel parameters for SAP HANA ----
# echo "[INFO] Applying kernel parameters for SAP HANA..."
# sudo tee /etc/sysctl.d/99-hana.conf >/dev/null <<'EOF'
# fs.file-max=20000000
# fs.aio-max-nr=262144
# vm.memory_failure_early_kill=1
# vm.max_map_count=135217728
# net.ipv4.ip_local_port_range=40000 60999
# EOF
# sudo sysctl --system


# # ---- Create persistent storage path ----
# sudo mkdir -p /data/hxe /opt/hana /opt/scripts
# sudo chmod -R 777 /data /opt


# # ========= ENABLE INGRESS =========
# if ! kubectl get ns ingress-nginx &>/dev/null; then
#   echo "🧩 Enabling ingress controller..."
#   minikube addons enable ingress
# fi
# kubectl wait -n ingress-nginx \
#   --for=condition=Ready pod \
#   -l app.kubernetes.io/component=controller \
#   --timeout=180s || true

# # ========= TLS SECRET =========
# TMPDIR=$(mktemp -d)
# aws s3 cp "$S3_CERT_PATH" "$TMPDIR/origin.crt" --quiet || true
# aws s3 cp "$S3_KEY_PATH" "$TMPDIR/origin.key" --quiet || true

# if [[ -f "$TMPDIR/origin.crt" && -f "$TMPDIR/origin.key" ]]; then
#   kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
#   kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
#   kubectl create secret tls "$SECRET_NAME" \
#     --cert="$TMPDIR/origin.crt" \
#     --key="$TMPDIR/origin.key" \
#     -n "$NAMESPACE"
#   echo "✅ TLS secret created in namespace '$NAMESPACE'"
# else
#   echo "⚠️ TLS certificate files not found in S3. Skipping."
# fi
# rm -rf "$TMPDIR"

# # ========= CLOUDFLARE TUNNELS =========
# echo "🧭 Checking Cloudflare tunnels..."
# sudo mkdir -p "$LOCAL_CF_DIR"
# sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

# if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
#   echo "❌ Cloudflare not authenticated. Run 'cloudflared login' first."
#   exit 1
# fi

# # Include Vault in tunnels list
# APPS=("dashboard" "hello" "ads" "vault")
# for APP in "${APPS[@]}"; do
#   JSON_FILE="${LOCAL_CF_DIR}/${APP}-tunnel.json"
#   S3_FILE="${S3_TUNNEL_PATH}/${APP}-tunnel.json"

#   echo "🔹 Processing tunnel for ${APP}..."

#   if aws s3 ls "${S3_FILE}" >/dev/null 2>&1; then
#     echo "✅ Found in S3. Downloading..."
#     aws s3 cp "${S3_FILE}" "${JSON_FILE}" --quiet
#   elif cloudflared tunnel list 2>/dev/null | grep -q "${APP}-tunnel"; then
#     echo "✅ Tunnel exists in Cloudflare. Exporting credentials..."
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   else
#     echo "🌐 Creating new tunnel: ${APP}-tunnel"
#     cloudflared tunnel create "${APP}-tunnel"
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   fi

#   sudo chown ec2-user:ec2-user "${JSON_FILE}"
#   sudo chmod 600 "${JSON_FILE}"

#   echo "⬆️ Uploading ${APP}-tunnel.json to S3..."
#   aws s3 cp "${JSON_FILE}" "${S3_FILE}" --quiet
# done


# # ========= VAULT CONFIG =========
# echo "🔐 Setting up Vault persistent data & tunnel..."

# # Create persistent data directory
# sudo mkdir -p /data/vault
# sudo chmod -R 777 /data/vault

# # Retrieve Vault tunnel credentials from S3 if available
# VAULT_TUNNEL_JSON="${LOCAL_CF_DIR}/vault-tunnel.json"
# aws s3 cp "${S3_TUNNEL_PATH}/vault-tunnel.json" "${VAULT_TUNNEL_JSON}" --quiet || true

# if [[ -f "${VAULT_TUNNEL_JSON}" ]]; then
#   echo "✅ Vault tunnel credentials ready at ${VAULT_TUNNEL_JSON}"
# else
#   echo "⚠️ Vault tunnel not found in S3. Will need to run manually after Cloudflare login."
# fi

# # Precreate Vault namespace & secret placeholder
# kubectl create ns vault --dry-run=client -o yaml | kubectl apply -f -
# kubectl -n vault create secret generic vault-config --from-literal=initialized="false" --dry-run=client -o yaml | kubectl apply -f -
# echo "✅ Vault namespace and config secret initialized."


# # ========= RECORD ENVIRONMENT =========
# CLUSTER_IP=$(minikube ip)
# sudo mkdir -p /etc/minikube

# cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
# {
#   "namespace": "$NAMESPACE",
#   "vault_namespace": "vault",
#   "cluster_ip": "$CLUSTER_IP",
#   "domain": "$DOMAIN",
#   "tunnels": {
#     "dashboard": "${S3_TUNNEL_PATH}/dashboard-tunnel.json",
#     "hello": "${S3_TUNNEL_PATH}/hello-tunnel.json",
#     "ads": "${S3_TUNNEL_PATH}/ads-tunnel.json",
#     "vault": "${S3_TUNNEL_PATH}/vault-tunnel.json"
#   }
# }
# EOF

# echo "💾 Environment info saved:"
# cat /etc/minikube/env-info.json

# echo "🎯 Global setup complete with Vault preconfigured and Cloudflare tunnels synchronized to S3."


# #!/bin/bash
# set -euo pipefail

# # ========= GLOBAL CONFIG =========
# DOMAIN="ryandemolab.app"
# S3_BUCKET="ryandevlab-bucket"
# S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
# S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
# S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
# SECRET_NAME="cloudflare-cert"
# NAMESPACE="demo"
# LOCAL_CF_DIR="/home/ec2-user/.cloudflared"

# echo "🌍 Setting up global environment for Minikube + Cloudflare (${DOMAIN})..."

# # ========= INSTALL DEPENDENCIES =========
# sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

# # --- Cloudflared ---
# if ! command -v cloudflared &>/dev/null; then
#   ARCH=$(uname -m)
#   [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
#   echo "📦 Installing Cloudflared..."
#   sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
#        -o /usr/local/bin/cloudflared
#   sudo chmod +x /usr/local/bin/cloudflared
# fi

# # --- Passwordless sudo for ec2-user ---
# if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
#   echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user >/dev/null
#   sudo chmod 440 /etc/sudoers.d/ec2-user
#   echo "✅ ec2-user granted passwordless sudo"
# fi

# # ========= INSTALL MINIKUBE / HELM / KUBECTL =========
# if ! command -v kubectl &>/dev/null; then
#   echo "📦 Installing kubectl..."
#   curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
#   chmod +x kubectl && sudo mv kubectl /usr/local/bin/
# fi

# if ! command -v minikube &>/dev/null; then
#   echo "📦 Installing Minikube..."
#   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
#   chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
# fi

# if ! command -v helm &>/dev/null; then
#   echo "📦 Installing Helm..."
#   curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
#   tar -zxf helm-v3.13.1-linux-amd64.tar.gz >/dev/null
#   sudo mv linux-amd64/helm /usr/local/bin/helm
#   rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
# fi

# # ========= PREVENT DOCKER PATCH FAILURE =========
# echo "⚙️  Creating fake Docker service to prevent Minikube patch bug..."
# sudo tee /etc/systemd/system/docker.service >/dev/null <<'EOF'
# [Unit]
# Description=Fake Docker placeholder
# [Service]
# Type=oneshot
# ExecStart=/bin/true
# [Install]
# WantedBy=multi-user.target
# EOF
# sudo systemctl daemon-reload

# # ========= SYSTEM RESOURCES =========
# HOST_CPUS=$(nproc)
# HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')  # MB
# REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
# REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

# echo "🧠 Host: ${HOST_CPUS} CPUs, ${HOST_MEM}MB RAM"
# echo "⚙️  Using Minikube config → CPUs=${REQ_CPUS}, Memory=${REQ_MEM}MB"

# # ========= CLEANUP OLD ARTIFACTS =========
# echo "🧹 Cleaning old Minikube/Podman artifacts..."
# minikube delete --all --purge || true
# sudo podman rm -f $(sudo podman ps -aq --filter "label=name.minikube.sigs.k8s.io") 2>/dev/null || true
# sudo podman volume rm -f $(sudo podman volume ls -q | grep minikube) 2>/dev/null || true
# sudo podman volume prune -f || true

# # ========= PREPARE STORAGE =========
# sudo mkdir -p /data/minikube /data/hxe /opt/hana /opt/scripts
# sudo chown -R ec2-user:ec2-user /data
# sudo chmod -R 777 /data /opt

# # ========= START MINIKUBE =========
# echo "🚀 Starting Minikube (Podman driver) cleanly..."
# export MINIKUBE_FORCE_SYSTEMD=false
# export MINIKUBE_ENABLE_DOCKER=false

# minikube start \
#   --driver=podman \
#   --container-runtime=cri-o \
#   --mount=true \
#   --mount-string="/data/minikube:/var/lib/minikube" \
#   --cpus="${REQ_CPUS}" \
#   --memory="${REQ_MEM}" \
#   --disk-size=50g \
#   --force

# # ========= AUTO-START ON REBOOT =========
# echo "🛠️  Enabling Minikube auto-start on EC2 reboot..."
# sudo tee /etc/systemd/system/minikube-autostart.service >/dev/null <<EOF
# [Unit]
# Description=Auto-start Minikube on EC2 boot
# After=network-online.target
# Wants=network-online.target

# [Service]
# Type=oneshot
# ExecStart=/usr/local/bin/minikube start --driver=podman --container-runtime=cri-o --mount=true --mount-string="/data/minikube:/var/lib/minikube" --force
# RemainAfterExit=yes
# User=ec2-user

# [Install]
# WantedBy=multi-user.target
# EOF

# sudo systemctl daemon-reload
# sudo systemctl enable minikube-autostart.service

# # ========= VERIFY NODE =========
# kubectl wait --for=condition=Ready node --all --timeout=180s || true

# # ========= ENABLE INGRESS =========
# if ! kubectl get ns ingress-nginx &>/dev/null; then
#   echo "🧩 Enabling ingress controller..."
#   minikube addons enable ingress
# fi
# kubectl wait -n ingress-nginx \
#   --for=condition=Ready pod \
#   -l app.kubernetes.io/component=controller \
#   --timeout=180s || true

# # ========= TLS SECRET =========
# TMPDIR=$(mktemp -d)
# aws s3 cp "$S3_CERT_PATH" "$TMPDIR/origin.crt" --quiet || true
# aws s3 cp "$S3_KEY_PATH" "$TMPDIR/origin.key" --quiet || true
# kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# if [[ -f "$TMPDIR/origin.crt" && -f "$TMPDIR/origin.key" ]]; then
#   kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
#   kubectl create secret tls "$SECRET_NAME" \
#     --cert="$TMPDIR/origin.crt" \
#     --key="$TMPDIR/origin.key" \
#     -n "$NAMESPACE"
#   echo "✅ TLS secret created in namespace '$NAMESPACE'"
# else
#   echo "⚠️  TLS certificate files not found in S3. Skipping."
# fi
# rm -rf "$TMPDIR"

# # ========= CLOUDFLARE TUNNELS =========
# echo "🧭 Syncing Cloudflare tunnels..."
# sudo mkdir -p "$LOCAL_CF_DIR"
# sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

# if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
#   echo "❌ Cloudflare not authenticated. Run 'cloudflared login' first."
#   exit 1
# fi

# APPS=("dashboard" "hello" "ads" "vault")
# for APP in "${APPS[@]}"; do
#   JSON_FILE="${LOCAL_CF_DIR}/${APP}-tunnel.json"
#   S3_FILE="${S3_TUNNEL_PATH}/${APP}-tunnel.json"
#   echo "🔹 Processing tunnel for ${APP}..."

#   if aws s3 ls "${S3_FILE}" >/dev/null 2>&1; then
#     aws s3 cp "${S3_FILE}" "${JSON_FILE}" --quiet
#   elif cloudflared tunnel list 2>/dev/null | grep -q "${APP}-tunnel"; then
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   else
#     cloudflared tunnel create "${APP}-tunnel"
#     cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
#   fi

#   sudo chown ec2-user:ec2-user "${JSON_FILE}"
#   sudo chmod 600 "${JSON_FILE}"
#   aws s3 cp "${JSON_FILE}" "${S3_FILE}" --quiet
# done

# # ========= RECORD ENVIRONMENT =========
# CLUSTER_IP=$(minikube ip)
# sudo mkdir -p /etc/minikube
# cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
# {
#   "namespace": "$NAMESPACE",
#   "cluster_ip": "$CLUSTER_IP",
#   "domain": "$DOMAIN",
#   "tunnels": {
#     "dashboard": "${S3_TUNNEL_PATH}/dashboard-tunnel.json",
#     "hello": "${S3_TUNNEL_PATH}/hello-tunnel.json",
#     "ads": "${S3_TUNNEL_PATH}/ads-tunnel.json",
#     "vault": "${S3_TUNNEL_PATH}/vault-tunnel.json"
#   }
# }
# EOF

# echo "💾 Environment info saved:"
# cat /etc/minikube/env-info.json

# echo "🎯 Global setup complete — all workloads will use namespace '$NAMESPACE'."


#!/bin/bash
set -euo pipefail

# ========= GLOBAL CONFIG =========
DOMAIN="ryandemolab.app"
S3_BUCKET="ryandevlab-bucket"
S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
SECRET_NAME="cloudflare-cert"
NAMESPACE="demo"
LOCAL_CF_DIR="/home/ec2-user/.cloudflared"

echo "🌍 Setting up global environment for Minikube + Cloudflare (${DOMAIN})..."

# ========= INSTALL DEPENDENCIES =========
sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

# --- Cloudflared ---
if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
       -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# --- Passwordless sudo for ec2-user ---
if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
  echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user >/dev/null
  sudo chmod 440 /etc/sudoers.d/ec2-user
  echo "✅ ec2-user granted passwordless sudo"
fi

# ========= INSTALL MINIKUBE / HELM / KUBECTL =========
if ! command -v kubectl &>/dev/null; then
  echo "📦 Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

if ! command -v minikube &>/dev/null; then
  echo "📦 Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

if ! command -v helm &>/dev/null; then
  echo "📦 Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxf helm-v3.13.1-linux-amd64.tar.gz >/dev/null
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# ========= PREVENT DOCKER PATCH FAILURE =========
echo "⚙️  Creating fake Docker service to prevent Minikube patch bug..."
sudo tee /etc/systemd/system/docker.service >/dev/null <<'EOF'
[Unit]
Description=Fake Docker placeholder
[Service]
Type=oneshot
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload

# ========= SYSTEM RESOURCES =========
HOST_CPUS=$(nproc)
HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')  # MB
REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

echo "🧠 Host: ${HOST_CPUS} CPUs, ${HOST_MEM}MB RAM"
echo "⚙️  Using Minikube config → CPUs=${REQ_CPUS}, Memory=${REQ_MEM}MB"

# ========= CLEANUP OLD ARTIFACTS =========
echo "🧹 Cleaning old Minikube/Podman artifacts..."
minikube delete --all --purge || true
sudo podman rm -f $(sudo podman ps -aq --filter "label=name.minikube.sigs.k8s.io") 2>/dev/null || true
sudo podman volume rm -f $(sudo podman volume ls -q | grep minikube) 2>/dev/null || true
sudo podman volume prune -f || true

# ========= PREPARE STORAGE =========
sudo mkdir -p /data/minikube /data/hxe /data/vault /opt/hana /opt/scripts
sudo chown -R ec2-user:ec2-user /data
sudo chmod -R 777 /data /opt

# ========= SAP HANA KERNEL PARAMETERS =========
echo "⚙️  Applying kernel parameters for SAP HANA compatibility..."
sudo tee /etc/sysctl.d/99-hana.conf >/dev/null <<'EOF'
fs.file-max=20000000
fs.aio-max-nr=262144
vm.memory_failure_early_kill=1
vm.max_map_count=135217728
net.ipv4.ip_local_port_range=40000 60999
EOF
sudo sysctl --system >/dev/null 2>&1 || true

# ========= START MINIKUBE =========
echo "🚀 Starting Minikube (Podman driver) cleanly..."
export MINIKUBE_FORCE_SYSTEMD=false
export MINIKUBE_ENABLE_DOCKER=false

minikube start \
  --driver=podman \
  --container-runtime=cri-o \
  --mount=true \
  --mount-string="/data/minikube:/var/lib/minikube" \
  --cpus="${REQ_CPUS}" \
  --memory="${REQ_MEM}" \
  --disk-size=50g \
  --force

# ========= AUTO-START ON REBOOT =========
echo "🛠️  Enabling Minikube auto-start on EC2 reboot..."
sudo tee /etc/systemd/system/minikube-autostart.service >/dev/null <<EOF
[Unit]
Description=Auto-start Minikube on EC2 boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/minikube start --driver=podman --container-runtime=cri-o --mount=true --mount-string="/data/minikube:/var/lib/minikube" --force
RemainAfterExit=yes
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable minikube-autostart.service

# ========= VERIFY NODE =========
kubectl wait --for=condition=Ready node --all --timeout=180s || true

# ========= ENABLE INGRESS =========
if ! kubectl get ns ingress-nginx &>/dev/null; then
  echo "🧩 Enabling ingress controller..."
  minikube addons enable ingress
fi
kubectl wait -n ingress-nginx \
  --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller \
  --timeout=180s || true

# ========= TLS SECRET =========
TMPDIR=$(mktemp -d)
aws s3 cp "$S3_CERT_PATH" "$TMPDIR/origin.crt" --quiet || true
aws s3 cp "$S3_KEY_PATH" "$TMPDIR/origin.key" --quiet || true
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if [[ -f "$TMPDIR/origin.crt" && -f "$TMPDIR/origin.key" ]]; then
  kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
  kubectl create secret tls "$SECRET_NAME" \
    --cert="$TMPDIR/origin.crt" \
    --key="$TMPDIR/origin.key" \
    -n "$NAMESPACE"
  echo "✅ TLS secret created in namespace '$NAMESPACE'"
else
  echo "⚠️  TLS certificate files not found in S3. Skipping."
fi
rm -rf "$TMPDIR"

# ========= CLOUDFLARE TUNNELS =========
echo "🧭 Syncing Cloudflare tunnels..."
sudo mkdir -p "$LOCAL_CF_DIR"
sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
  echo "❌ Cloudflare not authenticated. Run 'cloudflared login' first."
  exit 1
fi

APPS=("dashboard" "hello" "ads" "vault")
for APP in "${APPS[@]}"; do
  JSON_FILE="${LOCAL_CF_DIR}/${APP}-tunnel.json"
  S3_FILE="${S3_TUNNEL_PATH}/${APP}-tunnel.json"
  echo "🔹 Processing tunnel for ${APP}..."

  if aws s3 ls "${S3_FILE}" >/dev/null 2>&1; then
    aws s3 cp "${S3_FILE}" "${JSON_FILE}" --quiet
  elif cloudflared tunnel list 2>/dev/null | grep -q "${APP}-tunnel"; then
    cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
  else
    cloudflared tunnel create "${APP}-tunnel"
    cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
  fi

  sudo chown ec2-user:ec2-user "${JSON_FILE}"
  sudo chmod 600 "${JSON_FILE}"
  aws s3 cp "${JSON_FILE}" "${S3_FILE}" --quiet
done

# ========= VAULT PRECONFIGURATION =========
echo "🔐 Preconfiguring Vault persistence and namespace..."
sudo mkdir -p /data/vault && sudo chmod -R 777 /data/vault
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic vault-config \
  --from-literal=initialized="false" --dry-run=client -o yaml | kubectl apply -f -

# ========= RECORD ENVIRONMENT =========
CLUSTER_IP=$(minikube ip)
sudo mkdir -p /etc/minikube
cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
{
  "namespace": "$NAMESPACE",
  "cluster_ip": "$CLUSTER_IP",
  "domain": "$DOMAIN",
  "tunnels": {
    "dashboard": "${S3_TUNNEL_PATH}/dashboard-tunnel.json",
    "hello": "${S3_TUNNEL_PATH}/hello-tunnel.json",
    "ads": "${S3_TUNNEL_PATH}/ads-tunnel.json",
    "vault": "${S3_TUNNEL_PATH}/vault-tunnel.json"
  }
}
EOF

echo "💾 Environment info saved:"
cat /etc/minikube/env-info.json

echo "🎯 Global setup complete — all workloads (Vault, HANA, Dashboard) use namespace '$NAMESPACE'."
