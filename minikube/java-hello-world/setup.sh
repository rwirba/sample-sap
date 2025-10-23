#!/bin/bash
set -e

echo "🔧 Installing Minikube environment on RHEL 9..."

# Install dependencies
sudo dnf install -y conntrack curl wget unzip podman

# Install kubectl
if ! command -v kubectl &> /dev/null; then
  echo "📦 Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi

# Install Minikube
if ! command -v minikube &> /dev/null; then
  echo "📦 Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64
  sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

# Install Helm
if ! command -v helm &> /dev/null; then
  echo "📦 Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxvf helm-v3.13.1-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# Start Minikube with Podman
if ! minikube status | grep -q "Running"; then
  echo "🚀 Starting Minikube with Podman driver..."
  minikube start --driver=podman --force
fi 

# Get Minikube IP
MINIKUBE_IP=$(minikube ip)

# Set NodePort manually or extract dynamically later
NODEPORT=32694  # Replace with dynamic extraction if needed

# Route EC2 port 80 to Minikube NodePort
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT}
sudo iptables -t nat -A POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE

# Enable ingress addon
if ! kubectl get pods -n ingress-nginx &> /dev/null; then
  echo "🌐 Enabling NGINX ingress controller..."
  minikube addons enable ingress
  echo "⏳ Waiting for ingress controller to be ready..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=Ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s
fi

echo "✅ Minikube setup complete with ingress controller enabled."