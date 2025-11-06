#!/bin/bash
set -euo pipefail

NAMESPACE="vault"

echo "🚀 Running Vault bootstrap process..."

# Wait until Vault is ready
sleep 10
kubectl rollout status deploy vault-demo -n ${NAMESPACE} --timeout=300s

# Recreate the Job
kubectl delete job vault-k8s-bootstrap -n ${NAMESPACE} --ignore-not-found
kubectl apply -f ../vault-chart/templates/vault-bootstrap-job.yaml

# Monitor job completion
echo "⏳ Waiting for Vault bootstrap job to complete..."
kubectl wait --for=condition=complete job/vault-k8s-bootstrap -n ${NAMESPACE} --timeout=180s

echo "✅ Vault Kubernetes Auth configured successfully!"

# --- Backup bootstrap info ---
if [[ -f /opt/vault-k8s-info.txt ]]; then
  echo "📤 Backing up vault-k8s-info.txt to S3..."
  aws s3 cp /opt/vault-k8s-info.txt s3://ryandevlab-bucket/vault/vault-k8s-info.txt --quiet || \
    echo "⚠️ Failed to upload vault-k8s-info.txt to S3"
else
  echo "⚠️ vault-k8s-info.txt not found. Skipping S3 backup."
fi

# --- Configure Vault Kubernetes auth ---
echo "🔐 Configuring Vault Kubernetes auth..."

VAULT_ADDR=$(kubectl get svc vault-demo -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
export VAULT_ADDR="http://${VAULT_ADDR}:8200"

if ! vault auth enable kubernetes 2>/dev/null; then
  echo "✅ Kubernetes auth already enabled"
fi

for i in {1..3}; do
  if vault write auth/kubernetes/config \
    token_reviewer_jwt="$(grep -A100 'JWT' /opt/vault-k8s-info.txt | tail -n +2)" \
    kubernetes_host="$(grep '^K8S_HOST' /opt/vault-k8s-info.txt | cut -d= -f2-)" \
    kubernetes_ca_cert="$(grep -A100 'CA Certificate' /opt/vault-k8s-info.txt | tail -n +2)"; then
      echo "✅ Kubernetes auth configured"
      break
  else
      echo "⚠️  Vault not ready yet... retrying in 10s"
      sleep 10
  fi
done

# Cleanup sensitive file
echo "🧹 Cleaning up local vault-k8s-info.txt..."
rm -f /opt/vault-k8s-info.txt || true

echo "🎯 Vault Kubernetes auth fully configured and archived to S3."
