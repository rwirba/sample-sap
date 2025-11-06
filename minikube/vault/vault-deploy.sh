#!/bin/bash
set -euo pipefail

APP_NAME="vault"
CHART_PATH="./vault-chart"
NAMESPACE="demo"

echo "🚀 Deploying Vault to Minikube..."

# Create namespace if missing
kubectl get ns "${NAMESPACE}" &>/dev/null || kubectl create ns "${NAMESPACE}"

# Deploy Helm chart
helm upgrade --install vault-demo "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --wait

# Wait for pod readiness
echo "⏳ Waiting for Vault pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=vault-demo -n "${NAMESPACE}" --timeout=180s

# Show service details
echo "✅ Vault deployed successfully!"
kubectl get pods,svc,ingress -n "${NAMESPACE}"

#
