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

# Enable ingress
if ! kubectl get pods -n ingress-nginx &> /dev/null; then
  echo "🌐 Enabling NGINX ingress..."
  minikube addons enable ingress
fi

echo "✅ Minikube setup complete."