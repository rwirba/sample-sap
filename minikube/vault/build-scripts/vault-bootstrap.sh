#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# Bootstrap Vault Kubernetes Auth Integration (Helm-managed)
# Everything runs in namespace "demo"
# -------------------------------------------------------------------

NAMESPACE="demo"
OUTPUT_FILE="/opt/vault-k8s-info.txt"
CHART_PATH="../vault-chart"
TIMEOUT="10m"

echo "🚀 Starting Vault bootstrap in namespace: ${NAMESPACE}"

# --- Ensure Vault deployment is ready ---
echo "⏳ Checking Vault deployment rollout..."
kubectl rollout status deploy vault-demo -n "${NAMESPACE}" --timeout="${TIMEOUT}"

# --- Recreate and apply Helm-rendered bootstrap job ---
echo "🔁 Recreating Vault bootstrap job..."
kubectl delete job vault-k8s-bootstrap -n "${NAMESPACE}" --ignore-not-found

echo "📦 Rendering Helm template for vault-bootstrap-job..."
helm template vault-demo "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --show-only templates/vault-bootstrap-job.yaml | kubectl apply -f -

# --- Wait for job completion ---
echo "🕒 Waiting for Vault bootstrap job to complete..."
if ! kubectl wait --for=condition=complete job/vault-k8s-bootstrap -n "${NAMESPACE}" --timeout="${TIMEOUT}"; then
  echo "❌ Vault bootstrap job did not complete successfully. Logs:"
  kubectl logs job/vault-k8s-bootstrap -n "${NAMESPACE}" || true
  exit 1
fi

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

echo "🧹 Cleaning up sensitive credential file..."
rm -f "${OUTPUT_FILE}" || true

echo "🎯 Vault Kubernetes Auth bootstrap completed successfully."
