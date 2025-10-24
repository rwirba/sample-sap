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
sudo dnf install -y conntrack curl wget vim unzip podman jq awscli

# kubectl
if ! command -v kubectl &> /dev/null; then
  echo "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

# minikube
if ! command -v minikube &> /dev/null; then
  echo "Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

# helm
if ! command -v helm &> /dev/null; then
  echo "Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxvf helm-v3.13.1-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# start minikube
if ! minikube status | grep -q "Running"; then
  echo "🚀 Starting Minikube with Podman driver..."
  minikube start --driver=podman --force
else
  echo "✅ Minikube already running."
fi

# wait for node
echo "⏳ Waiting for Minikube node to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s || true

# ingress
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
aws s3 cp "$S3_CERT_PATH" "$LOCAL_CERT_PATH" --quiet
aws s3 cp "$S3_KEY_PATH" "$LOCAL_KEY_PATH" --quiet
kubectl create ns $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl delete secret $SECRET_NAME -n $NAMESPACE --ignore-not-found
kubectl create secret tls $SECRET_NAME --cert="$LOCAL_CERT_PATH" --key="$LOCAL_KEY_PATH" -n $NAMESPACE
rm -f "$LOCAL_CERT_PATH" "$LOCAL_KEY_PATH"
echo "✅ TLS secret created."

# Capture metadata for Cloudflare
CLUSTER_IP=$(minikube ip)
INGRESS_SVC=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o json | jq -r '.spec.clusterIP')
echo "📘 Saving cluster info to /etc/minikube/env-info.json"
sudo mkdir -p /etc/minikube
cat <<EOF | sudo tee /etc/minikube/env-info.json >/dev/null
{
  "namespace": "$NAMESPACE",
  "cluster_ip": "$CLUSTER_IP",
  "ingress_svc": "$INGRESS_SVC"
}
EOF
echo "✅ Environment info saved at /etc/minikube/env-info.json"
