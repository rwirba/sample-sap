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

# --- Passwordless sudo ---
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

# ========= START MINIKUBE =========
if ! minikube status | grep -q "Running"; then
  echo "🚀 Starting Minikube (Podman driver)..."
  minikube start --driver=podman --force
else
  echo "✅ Minikube already running."
fi

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

if [[ -f "$TMPDIR/origin.crt" && -f "$TMPDIR/origin.key" ]]; then
  kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
  kubectl create secret tls "$SECRET_NAME" \
    --cert="$TMPDIR/origin.crt" \
    --key="$TMPDIR/origin.key" \
    -n "$NAMESPACE"
  echo "✅ TLS secret created in namespace '$NAMESPACE'"
else
  echo "⚠️ TLS certificate files not found in S3. Skipping."
fi
rm -rf "$TMPDIR"

# ========= CLOUDFLARE TUNNELS =========
echo "🧭 Checking Cloudflare tunnels..."
sudo mkdir -p "$LOCAL_CF_DIR"
sudo chown -R ec2-user:ec2-user "$LOCAL_CF_DIR"

if [[ ! -f "$LOCAL_CF_DIR/cert.pem" ]]; then
  echo "❌ Cloudflare not authenticated. Run 'cloudflared login' first."
  exit 1
fi

APPS=("dashboard" "hello" "ads")
for APP in "${APPS[@]}"; do
  JSON_FILE="${LOCAL_CF_DIR}/${APP}-tunnel.json"
  S3_FILE="${S3_TUNNEL_PATH}/${APP}-tunnel.json"

  echo "🔹 Processing tunnel for ${APP}..."

  if aws s3 ls "${S3_FILE}" >/dev/null 2>&1; then
    echo "✅ Found in S3. Downloading..."
    aws s3 cp "${S3_FILE}" "${JSON_FILE}" --quiet
  elif cloudflared tunnel list 2>/dev/null | grep -q "${APP}-tunnel"; then
    echo "✅ Tunnel exists in Cloudflare. Exporting credentials..."
    cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
  else
    echo "🌐 Creating new tunnel: ${APP}-tunnel"
    cloudflared tunnel create "${APP}-tunnel"
    cloudflared tunnel token --cred-file "${JSON_FILE}" "${APP}-tunnel"
  fi

  sudo chown ec2-user:ec2-user "${JSON_FILE}"
  sudo chmod 600 "${JSON_FILE}"

  echo "⬆️ Uploading ${APP}-tunnel.json to S3..."
  aws s3 cp "${JSON_FILE}" "${S3_FILE}" --quiet
done

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
    "ads": "${S3_TUNNEL_PATH}/ads-tunnel.json"
  }
}
EOF

echo "💾 Environment info saved:"
cat /etc/minikube/env-info.json

echo "🎯 Global setup complete with Cloudflare tunnels synchronized to S3."
