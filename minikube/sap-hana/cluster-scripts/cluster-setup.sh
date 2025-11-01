#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Cluster Setup — install all prerequisites
# -------------------------------------------------------------------
echo "[INFO] 🧩 Setting up cluster environment for SAP HANA..."

# --- Check kubectl ---
if ! command -v kubectl &>/dev/null; then
  echo "[INFO] Installing kubectl..."
  curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

# --- Check helm ---
if ! command -v helm &>/dev/null; then
  echo "[INFO] Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# --- Check minikube ---
if ! command -v minikube &>/dev/null; then
  echo "[INFO] Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
fi

# --- Start Minikube if not running ---
if ! minikube status | grep -q "Running"; then
  echo "[INFO] Starting Minikube cluster..."
  minikube start --cpus=6 --memory=24g --disk-size=100g
fi

# --- Enable ingress addon (optional) ---
minikube addons enable ingress || true

# --- Load SAP HANA image if already built ---
if podman image exists ryandevlab/sap-hana:1.0.0; then
  echo "[INFO] Loading local image into Minikube..."
  minikube image load ryandevlab/sap-hana:1.0.0
fi

echo
echo "[✅ SUCCESS] Minikube cluster is ready for SAP HANA deployment."
kubectl get nodes
