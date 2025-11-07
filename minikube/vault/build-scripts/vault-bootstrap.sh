#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# Bootstrap Vault Kubernetes Auth Integration
# Namespace: demo
# -------------------------------------------------------------------

NAMESPACE="demo"
OUTPUT_FILE="/opt/vault-k8s-info.txt"
BOOTSTRAP_JOB="../vault-chart/templates/vault-bootstrap-job.yaml"

echo "🚀 Starting Vault bootstrap in namespace: ${NAMESPACE}"

# --- Wait for Vault deployment readiness ---
echo "⏳ Checking Vault deployment..."
kubectl rollout status deploy vault-demo -n "${NAMESPACE}" --timeout=300s

# --- Recreate the bootstrap job (idempotent) ---
echo "🔁 Recreating Vault bootstrap job..."
kubectl delete job vault-k8s-bootstrap -n "${NAMESPACE}" --ignore-not-found
kubectl apply -f "${BOOTSTRAP_JOB}"

echo "🕒 Waiting for bootstrap job completion..."
kubectl wait --for=condition=complete job/vault-k8s-bootstrap -n "${NAMESPACE}" --timeout=300s || {
  echo "❌ Vault bootstrap job did not complete successfully."
  kubectl logs job/vault-k8s-bootstrap -n "${NAMESPACE}" || true
  exit 1
}

# --- Configure Vault Kubernetes Auth ---
VAULT_SVC_IP=$(kubectl get svc vault-demo -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}')
export VAULT_ADDR="http://${VAULT_SVC_IP}:8200"
echo "🔐 Using Vault address: ${VAULT_ADDR}"

if [[ ! -f "${OUTPUT_FILE}" ]]; then
  echo "⚠️  Missing file: ${OUTPUT_FILE}. Run extract-k8s-credentials.sh first."
  exit 1
fi

K8S_HOST=$(grep '^K8S_HOST' "${OUTPUT_FILE}" | cut -d= -f2-)
K8S_CA=$(awk '/CA Certificate/{flag=1;next}/JWT/{flag=0}flag' "${OUTPUT_FILE}")
K8S_JWT=$(awk '/JWT/{flag=1;next}flag' "${OUTPUT_FILE}")

vault auth enable kubernetes 2>/dev/null || echo "ℹ️  Kubernetes auth already enabled."

for i in {1..5}; do
  if vault write auth/kubernetes/config \
    token_reviewer_jwt="${K8S_JWT}" \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert="${K8S_CA}" >/dev/null 2>&1; then
      echo "✅ Vault Kubernetes auth configured successfully."
      break
  else
      echo "⚠️  Vault not ready yet, retrying in 10s..."
      sleep 10
  fi
done

echo "🧹 Cleaning up local credential file..."
rm -f "${OUTPUT_FILE}" || true

echo "🎯 Vault Kubernetes Auth bootstrap completed successfully."
