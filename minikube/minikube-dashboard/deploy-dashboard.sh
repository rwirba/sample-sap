#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Minikube Kubernetes Dashboard ingress and service..."

# Ensure namespace exists
if ! kubectl get ns kubernetes-dashboard &>/dev/null; then
  echo "📦 Creating namespace: kubernetes-dashboard"
  kubectl create ns kubernetes-dashboard
fi

# Apply ingress and service YAML
echo "🧱 Applying dashboard-ingress.yml..."
kubectl apply -f dashboard-ingress.yml

# Wait for resources to be ready
echo "⏳ Waiting for ingress to be applied..."
kubectl rollout status deployment/kubernetes-dashboard -n kubernetes-dashboard --timeout=90s || true

# Verify ingress address
echo "🔍 Current Ingress:"
kubectl get ingress -n kubernetes-dashboard

echo "✅ Dashboard ingress successfully applied."
