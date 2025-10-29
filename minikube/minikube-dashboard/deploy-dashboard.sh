#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Minikube Kubernetes Dashboard via Helm..."

APP_NAME="minikube-dashboard"
NAMESPACE="kubernetes-dashboard"
TOKEN_FILE="/etc/minikube/dashboard-token.txt"
S3_BUCKET="ryandevlab-bucket"
S3_TOKEN_PATH="s3://${S3_BUCKET}/dashboard-token.txt"

# --- Ensure namespace exists ---
if ! kubectl get ns "$NAMESPACE" &>/dev/null; then
  echo "📦 Creating namespace: $NAMESPACE"
  kubectl create ns "$NAMESPACE"
fi

# --- Install or upgrade the chart directly ---
if helm list -n "$NAMESPACE" | grep -q "$APP_NAME"; then
  echo "🔁 Upgrading existing Dashboard release..."
else
  echo "🧩 Installing new Dashboard release..."
fi

helm upgrade --install "$APP_NAME" ./minikube-dashboard-chart -n "$NAMESPACE" --create-namespace

# --- Wait for Dashboard pods to be ready ---
echo "⏳ Waiting for Dashboard pods to become ready..."
kubectl wait --for=condition=Ready pod -l k8s-app=kubernetes-dashboard -n "$NAMESPACE" --timeout=180s || true

# --- Verify ingress ---
echo "🔍 Current Ingress resources:"
kubectl get ingress -n "$NAMESPACE"

# --- Generate admin token ---
echo "🔑 Generating admin-user token..."
TOKEN=$(kubectl -n "$NAMESPACE" create token admin-user)

if [[ -z "$TOKEN" ]]; then
  echo "❌ Failed to generate token. Check admin-user service account and role binding."
  exit 1
fi

# --- Save token locally ---
sudo mkdir -p /etc/minikube
echo "$TOKEN" | sudo tee "$TOKEN_FILE" >/dev/null
sudo chmod 600 "$TOKEN_FILE"

# --- Upload token to S3 for central access ---
echo "⬆️ Uploading token to S3..."
aws s3 cp "$TOKEN_FILE" "$S3_TOKEN_PATH" --quiet || echo "⚠️ Skipped S3 upload (check AWS CLI credentials)."

# --- Summary ---
echo "✅ Dashboard deployed successfully!"
echo "🔑 Token saved to: $TOKEN_FILE"
echo "☁️ Token uploaded to: $S3_TOKEN_PATH"
echo "🌐 Access it at: https://dashboard.ryandemolab.app"
