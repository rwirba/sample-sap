#!/bin/bash
set -euo pipefail

S3_CERT_PATH="s3://ryandevlab-bucket/origin.crt"
S3_KEY_PATH="s3://ryandevlab-bucket/origin.key"
LOCAL_CERT_PATH="$(pwd)/origin.crt"
LOCAL_KEY_PATH="$(pwd)/origin.key"
SECRET_NAME="cloudflare-cert"
NAMESPACE="demo"

echo "🔧 Installing Minikube environment on RHEL 9..."

# --- Dependencies ---
sudo dnf install -y conntrack curl wget vim unzip podman jq awscli policycoreutils || true

# --- Ensure ec2-user is a sudoer ---
if ! sudo grep -q "^ec2-user" /etc/sudoers.d/ec2-user 2>/dev/null; then
  echo "ec2-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ec2-user > /dev/null
  sudo chmod 440 /etc/sudoers.d/ec2-user
  echo "✅ ec2-user added to sudoers with passwordless privileges"
else
  echo "✅ ec2-user already has sudo privileges"
fi

# --- kubectl ---
if ! command -v kubectl &>/dev/null; then
  echo "📦 Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

# --- Minikube ---
if ! command -v minikube &>/dev/null; then
  echo "📦 Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

# --- Helm ---
if ! command -v helm &>/dev/null; then
  echo "📦 Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxvf helm-v3.13.1-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# --- Start Minikube ---
if ! minikube status | grep -q "Running"; then
  echo "🚀 Starting Minikube with Podman driver..."
  minikube start --driver=podman --force
else
  echo "✅ Minikube already running."
fi

# --- Wait for node ready ---
echo "⏳ Waiting for Minikube node to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s || true

# --- Enable ingress ---
if ! kubectl get ns ingress-nginx &>/dev/null; then
  echo "🧩 Enabling NGINX ingress controller..."
  minikube addons enable ingress
fi

echo "⏳ Waiting for ingress controller to start..."
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || true

echo "✅ Minikube + Ingress ready!"

# --- Download TLS cert from S3 ---
echo "🔒 Setting up Cloudflare TLS certificate from S3..."
aws s3 cp "$S3_CERT_PATH" "$LOCAL_CERT_PATH" --quiet
aws s3 cp "$S3_KEY_PATH" "$LOCAL_KEY_PATH" --quiet

# --- Create secret ---
kubectl create ns $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl delete secret $SECRET_NAME -n $NAMESPACE --ignore-not-found
kubectl create secret tls $SECRET_NAME --cert="$LOCAL_CERT_PATH" --key="$LOCAL_KEY_PATH" -n $NAMESPACE
rm -f "$LOCAL_CERT_PATH" "$LOCAL_KEY_PATH"
echo "✅ TLS secret created."

# --- Save cluster info for Cloudflare ---
CLUSTER_IP=$(minikube ip)
echo "📘 Saving cluster info to /etc/minikube/env-info.json"
sudo mkdir -p /etc/minikube
cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
{
  "namespace": "$NAMESPACE",
  "cluster_ip": "$CLUSTER_IP"
}
EOF
echo "✅ Environment info saved: Namespace=$NAMESPACE, Cluster IP=$CLUSTER_IP"
