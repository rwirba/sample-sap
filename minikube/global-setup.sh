#!/bin/bash
set -euo pipefail

# --- Global Config ---
S3_CERT_PATH="s3://ryandevlab-bucket/origin.crt"
S3_KEY_PATH="s3://ryandevlab-bucket/origin.key"
SECRET_NAME="cloudflare-cert"
NAMESPACE="demo"

echo "🌍 Setting up global environment for Minikube + Cloudflare"

# --- System Dependencies ---
sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

# --- Sudoer check ---
if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
  echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user >/dev/null
  sudo chmod 440 /etc/sudoers.d/ec2-user
  echo "✅ ec2-user granted passwordless sudo"
fi

# --- Install kubectl ---
if ! command -v kubectl &>/dev/null; then
  echo "📦 Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

# --- Install Minikube ---
if ! command -v minikube &>/dev/null; then
  echo "📦 Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

# --- Install Helm ---
if ! command -v helm &>/dev/null; then
  echo "📦 Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxvf helm-v3.13.1-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# --- Start Minikube with Podman ---
if ! minikube status | grep -q "Running"; then
  echo "🚀 Starting Minikube (Podman driver)..."
  minikube start --driver=podman --force
else
  echo "✅ Minikube already running."
fi

# --- Wait for cluster ready ---
echo "⏳ Waiting for Minikube node to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s || true

# --- Enable Ingress ---
if ! kubectl get ns ingress-nginx &>/dev/null; then
  echo "🧩 Enabling NGINX ingress controller..."
  minikube addons enable ingress
fi

echo "⏳ Waiting for ingress controller pods..."
kubectl wait -n ingress-nginx \
  --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller \
  --timeout=180s || true

echo "✅ Ingress is ready."

# --- Setup Cloudflare TLS secret ---
echo "🔒 Setting up Cloudflare certificate..."
TMPDIR=$(mktemp -d)
aws s3 cp "$S3_CERT_PATH" "$TMPDIR/origin.crt" --quiet
aws s3 cp "$S3_KEY_PATH" "$TMPDIR/origin.key" --quiet

kubectl create ns $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl delete secret $SECRET_NAME -n $NAMESPACE --ignore-not-found
kubectl create secret tls $SECRET_NAME \
  --cert="$TMPDIR/origin.crt" \
  --key="$TMPDIR/origin.key" \
  -n $NAMESPACE

rm -rf "$TMPDIR"
echo "✅ TLS secret '$SECRET_NAME' created in namespace '$NAMESPACE'"

# --- Save cluster IP info for app cloudflare scripts ---
CLUSTER_IP=$(minikube ip)
sudo mkdir -p /etc/minikube
cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
{
  "namespace": "$NAMESPACE",
  "cluster_ip": "$CLUSTER_IP"
}
EOF

echo "📘 Environment info saved: Namespace=$NAMESPACE, Cluster IP=$CLUSTER_IP"
echo "🎯 Global setup complete!"
