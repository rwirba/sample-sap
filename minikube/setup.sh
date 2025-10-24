#!/bin/bash
set -euo pipefail

S3_CERT_PATH="s3://ryandevlab-bucket/origin.crt"
S3_KEY_PATH="s3://ryandevlab-bucket/origin.key"
S3_TUNNEL_PATH="s3://ryandevlab-bucket/cloudflare-tunnel.json"
LOCAL_CERT_PATH="$(pwd)/origin.crt"
LOCAL_KEY_PATH="$(pwd)/origin.key"
SECRET_NAME="cloudflare-cert"
NAMESPACE="demo"
TUNNEL_ID="7fd52242-2178-43af-a8c3-4c7e123e276f"

# Add ec2-user to sudoers
if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
  echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user > /dev/null
  sudo chmod 440 /etc/sudoers.d/ec2-user
  echo "✅ ec2-user added to sudoers with passwordless privileges"
else
  echo "✅ ec2-user already has sudo privileges"
fi

echo "🚀 Installing Minikube environment on RHEL 9..."

# Install dependencies
sudo dnf install -y conntrack curl wget vim unzip podman jq awscli

# kubectl
if ! command -v kubectl &> /dev/null; then
  echo "📦 Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

# minikube
if ! command -v minikube &> /dev/null; then
  echo "📦 Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

# helm
if ! command -v helm &> /dev/null; then
  echo "📦 Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxvf helm-v3.13.1-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# Start minikube
if ! minikube status | grep -q "Running"; then
  echo "🚀 Starting Minikube with Podman driver..."
  minikube start --driver=podman --force
else
  echo "✅ Minikube already running."
fi

# Wait for node
echo "⏳ Waiting for Minikube node to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s || true

# Enable ingress
if ! kubectl get ns ingress-nginx &> /dev/null; then
  echo "🧩 Enabling NGINX ingress controller..."
  minikube addons enable ingress
fi

echo "⏳ Waiting for ingress controller to start..."
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || true

echo "✅ Minikube + Ingress ready!"

# TLS secret from S3
echo "🔒 Setting up Cloudflare TLS certificate from S3..."
aws s3 cp "$S3_CERT_PATH" "$LOCAL_CERT_PATH" --quiet || echo "⚠️ Failed to pull $S3_CERT_PATH"
aws s3 cp "$S3_KEY_PATH" "$LOCAL_KEY_PATH" --quiet || echo "⚠️ Failed to pull $S3_KEY_PATH"

kubectl create ns $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl delete secret $SECRET_NAME -n $NAMESPACE --ignore-not-found
kubectl create secret tls $SECRET_NAME --cert="$LOCAL_CERT_PATH" --key="$LOCAL_KEY_PATH" -n $NAMESPACE

rm -f "$LOCAL_CERT_PATH" "$LOCAL_KEY_PATH"
echo "✅ TLS secret created."

# Capture metadata for Cloudflare
CLUSTER_IP=$(minikube ip)
INGRESS_SVC=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o json | jq -r '.spec.clusterIP')
sudo mkdir -p /etc/minikube
cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
{
  "namespace": "$NAMESPACE",
  "cluster_ip": "$CLUSTER_IP",
  "ingress_svc": "$INGRESS_SVC"
}
EOF
echo "✅ Environment info saved at /etc/minikube/env-info.json"

# Cloudflared setup
echo "☁️ Installing and restoring Cloudflared..."
if ! command -v cloudflared &> /dev/null; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O /tmp/cloudflared.deb
  sudo dnf install -y /tmp/cloudflared.deb || sudo yum localinstall -y /tmp/cloudflared.deb
  sudo mv /usr/bin/cloudflared /usr/local/bin/cloudflared 2>/dev/null || true
  sudo chmod +x /usr/local/bin/cloudflared
fi

sudo mkdir -p /root/.cloudflared
sudo aws s3 cp "$S3_TUNNEL_PATH" "/root/.cloudflared/${TUNNEL_ID}.json" --quiet || echo "⚠️ No tunnel file found in S3, you may need to upload it first."
sudo chmod 600 /root/.cloudflared/*.json 2>/dev/null || true

# Create service if missing
if [ ! -f /etc/systemd/system/cloudflared.service ]; then
  echo "🛠️ Creating Cloudflared systemd service..."
  sudo tee /etc/systemd/system/cloudflared.service >/dev/null <<EOF
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
fi

sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared
sudo systemctl status cloudflared --no-pager

echo "🎯 Cloudflare + Minikube environment fully ready!"
