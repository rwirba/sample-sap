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
# sudo mkdir -p /data/minikube /data/hxe /data/vault /opt/hana /opt/scripts
# sudo chown -R ec2-user:ec2-user /data
# sudo chmod -R 777 /data /opt

# # ========= SAP HANA KERNEL PARAMETERS =========
# echo "⚙️  Applying kernel parameters for SAP HANA compatibility..."
# sudo tee /etc/sysctl.d/99-hana.conf >/dev/null <<'EOF'
# fs.file-max=20000000
# fs.aio-max-nr=262144
# vm.memory_failure_early_kill=1
# vm.max_map_count=135217728
# net.ipv4.ip_local_port_range=40000 60999
# EOF
# sudo sysctl --system >/dev/null 2>&1 || true

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

# # ========= VAULT PRECONFIGURATION =========
# echo "🔐 Preconfiguring Vault persistence and namespace..."
# sudo mkdir -p /data/vault && sudo chmod -R 777 /data/vault
# kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
# kubectl -n "$NAMESPACE" create secret generic vault-config \
#   --from-literal=initialized="false" --dry-run=client -o yaml | kubectl apply -f -

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

# echo "🎯 Global setup complete — all workloads (Vault, HANA, Dashboard) use namespace '$NAMESPACE'."


# #!/bin/bash
# set -euo pipefail

# # ==============================================================
# # 🌍 GLOBAL SETUP: Minikube + Cloudflare + Dashboard (demo ns)
# # ==============================================================

# DOMAIN="ryandemolab.app"
# S3_BUCKET="ryandevlab-bucket"
# S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
# S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
# S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
# SECRET_NAME="cloudflare-cert"
# NAMESPACE="demo"
# LOCAL_CF_DIR="/home/ec2-user/.cloudflared"

# echo "🌍 Starting full environment setup for Minikube + Dashboard (${DOMAIN})"

# # ==============================================================
# # 📦 INSTALL DEPENDENCIES
# # ==============================================================
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

# # ==============================================================
# # ⚙️ INSTALL MINIKUBE, HELM, KUBECTL
# # ==============================================================
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

# # ==============================================================
# # 🧠 MINIKUBE CONFIGURATION
# # ==============================================================
# HOST_CPUS=$(nproc)
# HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
# REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
# REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

# echo "🧠 Host: ${HOST_CPUS} CPUs, ${HOST_MEM}MB RAM → Using ${REQ_CPUS} CPUs / ${REQ_MEM}MB"

# sudo mkdir -p /data/minikube
# sudo chown -R ec2-user:ec2-user /data/minikube
# sudo chmod -R 777 /data/minikube

# # --- Start Minikube only if not running ---
# if minikube status | grep -q "host: Running"; then
#   echo "✅ Minikube already running — skipping startup only."
# else
#   if [[ -d /data/minikube && -n "$(ls -A /data/minikube 2>/dev/null)" ]]; then
#     echo "⚠️  /data/minikube not empty — assuming existing cluster, skipping start."
#   else
#     echo "🚀 Starting Minikube (Podman driver)..."
#     minikube start \
#       --driver=podman \
#       --container-runtime=cri-o \
#       --mount=true \
#       --mount-string="/data/minikube:/var/lib/minikube" \
#       --cpus="${REQ_CPUS}" \
#       --memory="${REQ_MEM}" \
#       --disk-size=50g \
#       --force
#   fi                # ← closes the inner “if [[ -d … ]]”
# fi                  # ← closes the outer “if minikube status …”


# # --- Auto-start service ---
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

# # ==============================================================
# # 🧩 INGRESS + CERTIFICATES
# # ==============================================================
# if ! kubectl get ns ingress-nginx &>/dev/null; then
#   minikube addons enable ingress
# fi
# kubectl wait -n ingress-nginx \
#   --for=condition=Ready pod \
#   -l app.kubernetes.io/component=controller \
#   --timeout=180s || true

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
#   echo "✅ TLS secret created in '$NAMESPACE'"
# else
#   echo "⚠️ TLS certificate not found in S3."
# fi
# rm -rf "$TMPDIR"

# # ==============================================================
# # 🧭 CLOUDFLARE TUNNELS
# # ==============================================================
# sudo mkdir -p "$LOCAL_CF_DIR"
# sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

# if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
#   echo "🌐 Cloudflare not authenticated. Launching browser login..."
#   echo "➡️  A browser window will open. Please log in and authorize this server."
  
#   # Run cloudflared login interactively
#   cloudflared login || {
#     echo "❌ Cloudflare login failed. Please retry manually."
#     exit 1
#   }

#   # Wait for the certificate to appear
#   echo "⏳ Waiting for Cloudflare authentication to complete..."
#   for i in {1..30}; do
#     if [[ -f "$LOCAL_CF_DIR/cert.pem" ]]; then
#       echo "✅ Cloudflare authenticated successfully."
#       break
#     fi
#     sleep 3
#   done

#   # Final check
#   if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
#     echo "❌ Authentication timed out (cert.pem not found)."
#     exit 1
#   fi
# else
#   echo "✅ Cloudflare already authenticated."
# fi


# # ==============================================================
# # 🧠 DEPLOY KUBERNETES DASHBOARD VIA HELM
# # ==============================================================

# echo "🧩 Deploying Kubernetes Dashboard via Helm repo..."

# # --- Ensure Helm repo is added ---
# helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard --force-update >/dev/null
# helm repo update >/dev/null

# # --- Pre-pull required images to speed up first deploy ---
# echo "📦 Pre-pulling Kubernetes Dashboard images..."
# for IMG in \
#   kubernetesui/dashboard:v2.7.0 \
#   kubernetesui/metrics-scraper:v1.0.8; do
#   echo "→ Pulling $IMG into Minikube cache..."
#   for i in {1..3}; do
#     if minikube image pull "$IMG"; then
#       echo "✅ Pulled $IMG"
#       break
#     else
#       echo "⚠️ Retry #$i for $IMG..."
#       sleep 10
#     fi
#   done
# done

# # --- Function to safely deploy via Helm with retry ---
# deploy_dashboard() {
#   helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
#     --namespace "$NAMESPACE" \
#     --create-namespace \
#     --set fullnameOverride="kubernetes-dashboard" \
#     --set ingress.enabled=true \
#     --set ingress.className=nginx \
#     --set ingress.hosts[0].host="dashboard.${DOMAIN}" \
#     --set service.type=ClusterIP \
#     --set service.port=443 \
#     --set service.targetPort=8443 \
#     --atomic --timeout 15m \
#     | grep -v "unrecognized format" || true
# }

# echo "🚀 Deploying Dashboard..."
# if ! deploy_dashboard; then
#   echo "⚠️ Dashboard deployment failed on first try, retrying once after 30 s..."
#   sleep 30
#   deploy_dashboard || echo "❌ Dashboard installation failed — continuing to next steps."
# fi

# # --- Wait for Dashboard pods to be ready ---
# echo "⏳ Waiting for Dashboard pods to be ready..."
# kubectl wait --for=condition=Ready pod -l "k8s-app=kubernetes-dashboard" -n "$NAMESPACE" --timeout=300s || true

# # --- Create admin user + RBAC ---
# echo "🔐 Ensuring admin-user RBAC setup..."
# cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
# apiVersion: v1
# kind: ServiceAccount
# metadata:
#   name: admin-user
#   namespace: ${NAMESPACE}
# ---
# apiVersion: rbac.authorization.k8s.io/v1
# kind: ClusterRoleBinding
# metadata:
#   name: admin-user-binding
# roleRef:
#   apiGroup: rbac.authorization.k8s.io
#   kind: ClusterRole
#   name: cluster-admin
# subjects:
#   - kind: ServiceAccount
#     name: admin-user
#     namespace: ${NAMESPACE}
# EOF

# # --- Generate admin token and upload to S3 ---
# TOKEN=$(kubectl -n "$NAMESPACE" create token admin-user --duration=24h || true)
# if [[ -n "$TOKEN" ]]; then
#   echo "$TOKEN" | sudo tee /etc/minikube/dashboard-token.txt >/dev/null
#   aws s3 cp /etc/minikube/dashboard-token.txt "s3://${S3_BUCKET}/dashboard-token.txt" --quiet || true
#   echo "✅ Dashboard admin token saved and uploaded to S3."
# else
#   echo "⚠️ Failed to generate dashboard token."
# fi

# # --- Expose Dashboard via Cloudflare Tunnel ---
# echo "🌐 Setting up Cloudflare tunnel for dashboard..."
# DASH_TUNNEL_JSON="${LOCAL_CF_DIR}/dashboard-tunnel.json"
# if [[ -f "$DASH_TUNNEL_JSON" ]]; then
#   cloudflared tunnel route dns dashboard-tunnel "dashboard.${DOMAIN}" || true
#   echo "✅ Cloudflare tunnel ready → https://dashboard.${DOMAIN}"
# else
#   echo "⚠️ Dashboard tunnel credentials not found, skipping tunnel setup."
# fi


#!/bin/bash
set -euo pipefail

# ==============================================================
# 🌍 GLOBAL SETUP — Minikube + Cloudflare + Dashboard (Demo)
# ==============================================================

DOMAIN="ryandemolab.app"
S3_BUCKET="ryandevlab-bucket"
S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
SECRET_NAME="cloudflare-cert"
NAMESPACE="demo"
LOCAL_CF_DIR="/home/ec2-user/.cloudflared"
TUNNEL_NAME="dashboard-tunnel"

echo "🌍 Starting environment setup for Minikube + Cloudflare (${DOMAIN})"

# ==============================================================
# 📦 DEPENDENCIES
# ==============================================================
sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

if ! command -v cloudflared &>/dev/null; then
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  echo "📦 Installing Cloudflared..."
  sudo curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" \
       -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

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

# ==============================================================
# ⚙️ MINIKUBE SETUP
# ==============================================================
HOST_CPUS=$(nproc)
HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

sudo mkdir -p /data/minikube
sudo chown -R ec2-user:ec2-user /data/minikube
sudo chmod -R 777 /data/minikube

if ! minikube status | grep -q "host: Running"; then
  echo "🚀 Starting Minikube (Podman driver)..."
  minikube start \
    --driver=podman \
    --container-runtime=cri-o \
    --mount=true \
    --mount-string="/data/minikube:/var/lib/minikube" \
    --cpus="${REQ_CPUS}" \
    --memory="${REQ_MEM}" \
    --disk-size=50g \
    --force
else
  echo "✅ Minikube already running."
fi

kubectl wait --for=condition=Ready node --all --timeout=180s || true
minikube addons enable ingress || true

kubectl wait -n ingress-nginx \
  --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller \
  --timeout=180s || true

# ==============================================================
# 🧩 TLS SECRET
# ==============================================================
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
  echo "✅ TLS secret '${SECRET_NAME}' created in '${NAMESPACE}'"
else
  echo "⚠️  TLS certs not found in S3"
fi
rm -rf "$TMPDIR"

# ==============================================================
# 🌐 CLOUDFLARE TUNNEL
# ==============================================================
sudo mkdir -p "$LOCAL_CF_DIR"
sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

TUNNEL_JSON="${LOCAL_CF_DIR}/${TUNNEL_NAME}.json"
S3_TUNNEL_FILE="${S3_TUNNEL_PATH}/${TUNNEL_NAME}.json"

if [[ ! -f "$TUNNEL_JSON" ]]; then
  if aws s3 ls "$S3_TUNNEL_FILE" >/dev/null 2>&1; then
    aws s3 cp "$S3_TUNNEL_FILE" "$TUNNEL_JSON" --quiet
  else
    echo "🌐 Creating Cloudflare tunnel: ${TUNNEL_NAME}"
    cloudflared tunnel create "$TUNNEL_NAME" || true
    aws s3 cp "$TUNNEL_JSON" "$S3_TUNNEL_FILE" --quiet || true
  fi
else
  echo "✅ Tunnel '${TUNNEL_NAME}' already exists — skipping creation"
fi

cat <<EOF | sudo tee /home/ec2-user/.cloudflared/config.yml >/dev/null
tunnel: ${TUNNEL_NAME}
credentials-file: ${TUNNEL_JSON}
ingress:
  - hostname: dashboard.${DOMAIN}
    service: http://127.0.0.1:80
  - service: http_status:404
EOF

sudo systemctl daemon-reload
sudo systemctl enable cloudflared-dashboard-tunnel.service >/dev/null 2>&1 || true
sudo systemctl restart cloudflared-dashboard-tunnel.service || true

# ==============================================================
# 🚀 DEPLOY KUBERNETES DASHBOARD
# ==============================================================
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard --force-update >/dev/null
helm repo update >/dev/null

helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set fullnameOverride="kubernetes-dashboard" \
  --set kong.enabled=true \
  --set ingress.enabled=false \
  --atomic --timeout 15m || true

kubectl wait --for=condition=Ready pod -l k8s-app=kubernetes-dashboard -n "$NAMESPACE" --timeout=300s || true

# ==============================================================
# 🧠 DASHBOARD INGRESS (FIXED FOR CLOUDFLARE)
# ==============================================================

echo "🧩 Applying dashboard ingress..."
cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - dashboard.${DOMAIN}
      secretName: ${SECRET_NAME}
  rules:
    - host: dashboard.${DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kubernetes-dashboard-kong-proxy
                port:
                  number: 8000
EOF

# ==============================================================
# 🔐 ADMIN USER + TOKEN
# ==============================================================
kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin-user
    namespace: ${NAMESPACE}
EOF

TOKEN=$(kubectl -n "$NAMESPACE" create token admin-user --duration=24h || true)
if [[ -n "$TOKEN" ]]; then
  echo "$TOKEN" | sudo tee /etc/minikube/dashboard-token.txt >/dev/null
  aws s3 cp /etc/minikube/dashboard-token.txt "s3://${S3_BUCKET}/dashboard-token.txt" --quiet || true
  echo "✅ Dashboard admin token uploaded to S3."
else
  echo "⚠️  Token generation failed."
fi

echo "🎯 Setup complete. Access your dashboard at:"
echo "👉 https://dashboard.${DOMAIN}"
