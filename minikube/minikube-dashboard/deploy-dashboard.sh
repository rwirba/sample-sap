#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Minikube Kubernetes Dashboard via Helm..."

APP_NAME="minikube-dashboard"
NAMESPACE="demo"
TOKEN_FILE="/etc/minikube/dashboard-token.txt"
S3_BUCKET="ryandevlab-bucket"
S3_TOKEN_PATH="s3://${S3_BUCKET}/dashboard-token.txt"

# --- Ensure Minikube is running ---
if ! minikube status | grep -q "host: Running"; then
  echo "⚙️  Minikube not running — starting automatically..."
  sudo systemctl start minikube-autostart.service || minikube start --driver=podman --mount=true --mount-string="/data/minikube:/var/lib/minikube" --force
else
  echo "✅ Minikube already running."
fi

# --- Wait for Kubernetes node to be ready ---
echo "⏳ Waiting for Kubernetes node to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=180s || true

# --- Ensure namespace exists ---
if ! kubectl get ns "$NAMESPACE" &>/dev/null; then
  echo "📦 Creating namespace: $NAMESPACE"
  kubectl create ns "$NAMESPACE"
fi

# --- Wait for ingress-nginx (important before Helm deploy) ---
echo "🧩 Ensuring ingress controller is ready..."
kubectl wait -n ingress-nginx --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s || true

# --- Deploy or upgrade the Dashboard chart ---
if helm list -n "$NAMESPACE" | grep -q "$APP_NAME"; then
  echo "🔁 Upgrading existing Dashboard release..."
else
  echo "🧩 Installing new Dashboard release..."
fi

helm upgrade --install "$APP_NAME" ./minikube-dashboard-chart \
  -n "$NAMESPACE" \
  --create-namespace \
  --set persistence.enabled=true \
  --atomic --timeout 5m

# --- Wait for Dashboard pods to be ready ---
echo "⏳ Waiting for Dashboard pods to become ready..."
kubectl wait --for=condition=Ready pod -l k8s-app=kubernetes-dashboard \
  -n "$NAMESPACE" --timeout=180s || true

# --- Verify ingress status ---
echo "🔍 Current Ingress resources:"
kubectl get ingress -n "$NAMESPACE" || true

# --- Ensure admin-user ServiceAccount + binding ---
echo "🔐 Ensuring admin-user RBAC configuration..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: demo
EOF

# --- Generate admin token ---
echo "🔑 Generating admin-user token..."
TOKEN=$(kubectl -n "$NAMESPACE" create token admin-user || true)

if [[ -z "$TOKEN" ]]; then
  echo "⚠️  Token not generated on first try, retrying..."
  sleep 5
  TOKEN=$(kubectl -n "$NAMESPACE" create token admin-user || true)
fi

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
if ! aws s3 cp "$TOKEN_FILE" "$S3_TOKEN_PATH" --quiet; then
  echo "⚠️ Upload failed, retrying..."
  sleep 3
  aws s3 cp "$TOKEN_FILE" "$S3_TOKEN_PATH" --quiet || echo "⚠️ Skipped S3 upload (check AWS CLI credentials)."
fi

# --- Summary ---
echo "✅ Dashboard deployed successfully!"
echo "🔑 Token saved to: $TOKEN_FILE"
echo "☁️ Token uploaded to: $S3_TOKEN_PATH"
echo "🌐 Access it at: https://dashboard.ryandemolab.app"
