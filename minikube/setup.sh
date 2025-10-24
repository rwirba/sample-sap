#!/bin/bash
set -e

S3_CERT_PATH="s3://ryandevlab-bucket/origin.crt"
S3_KEY_PATH="s3://ryandevlab-bucket/origin.key"
LOCAL_CERT_PATH="$(pwd)/origin.crt"
LOCAL_KEY_PATH="$(pwd)/origin.key"
SECRET_NAME="cloudflare-cert"
NAMESPACE="demo"

echo "Installing Minikube environment on RHEL 9..."

# Install dependencies
sudo dnf install -y conntrack curl wget unzip podman

# Install kubectl
if ! command -v kubectl &> /dev/null; then
  echo "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi

# Install Minikube
if ! command -v minikube &> /dev/null; then
  echo "Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64
  sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

# Install Helm
if ! command -v helm &> /dev/null; then
  echo "Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxvf helm-v3.13.1-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# Start Minikube with Podman
if ! minikube status | grep -q "Running"; then
  echo "🚀 Starting Minikube with Podman driver..."
  minikube start --driver=podman --force
else
  echo "✅ Minikube already running."
fi

# Wait until Minikube node is fully ready
echo "⏳ Waiting for Minikube node to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s || {
  echo "⚠️  Node not ready yet, checking status:"
  kubectl get nodes -o wide
}

# Enable ingress addon only after node is ready
if ! kubectl get ns ingress-nginx &> /dev/null; then
  echo "🧩 Enabling NGINX ingress controller..."
  minikube addons enable ingress
fi

# Wait for ingress controller pod
echo "⏳ Waiting for ingress controller to start..."
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || {
    echo "⚠️  Ingress controller failed to start on first attempt, retrying..."
    minikube addons disable ingress
    sleep 5
    minikube addons enable ingress
    kubectl wait --namespace ingress-nginx \
      --for=condition=Ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=180s
  }

echo "✅ Minikube is running and ingress-nginx is ready!"

echo "🔒 Setting up Cloudflare TLS certificate from S3..."

# Ensure AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo "⚙️ Installing AWS CLI..."
  sudo dnf install -y awscli || sudo yum install -y awscli
fi

# Download cert and key from S3
echo "📥 Downloading certificate and key from S3..."
aws s3 cp "$S3_CERT_PATH" "$LOCAL_CERT_PATH" --quiet || {
  echo "❌ Failed to download $S3_CERT_PATH"
  exit 1
}

aws s3 cp "$S3_KEY_PATH" "$LOCAL_KEY_PATH" --quiet || {
  echo "❌ Failed to download $S3_KEY_PATH"
  exit 1
}

# Verify files exist
if [[ -f "$LOCAL_CERT_PATH" && -f "$LOCAL_KEY_PATH" ]]; then
  echo "✅ Certificate and key successfully downloaded from S3."

  # Create namespace if missing
  if ! kubectl get ns $NAMESPACE &> /dev/null; then
    echo "📦 Creating namespace '$NAMESPACE'..."
    kubectl create ns $NAMESPACE
  fi

  # Recreate secret cleanly
  if kubectl get secret $SECRET_NAME -n $NAMESPACE &> /dev/null; then
    echo "🧹 Deleting existing TLS secret '$SECRET_NAME'..."
    kubectl delete secret $SECRET_NAME -n $NAMESPACE
  fi

  echo "🔐 Creating Kubernetes TLS secret '$SECRET_NAME'..."
  kubectl create secret tls $SECRET_NAME \
    --cert="$LOCAL_CERT_PATH" \
    --key="$LOCAL_KEY_PATH" \
    -n $NAMESPACE

  echo "✅ Cloudflare TLS secret '$SECRET_NAME' created successfully."
else
  echo "❌ Certificate or key file missing after S3 download."
  exit 1
fi
rm -f "$LOCAL_CERT_PATH" "$LOCAL_KEY_PATH"
