#!/bin/bash
set -euo pipefail

NAMESPACE="vault"

echo "🚀 Running Vault bootstrap process..."

# Wait until Vault is ready
kubectl rollout status deploy vault-demo -n ${NAMESPACE} --timeout=300s

# Create Job (it will auto-configure Vault)
kubectl delete job vault-k8s-bootstrap -n ${NAMESPACE} --ignore-not-found
kubectl apply -f ../vault-chart/templates/vault-bootstrap-job.yaml

# Monitor job
echo "⏳ Waiting for Vault bootstrap job to complete..."
kubectl wait --for=condition=complete job/vault-k8s-bootstrap -n ${NAMESPACE} --timeout=180s

echo "✅ Vault Kubernetes Auth configured successfully!"
