#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# Extract Kubernetes credentials for Vault ↔ Kubernetes integration
# Namespace: demo
# -------------------------------------------------------------------

NAMESPACE="demo"
SA_SECRET="vault-auth-token"
OUTPUT_FILE="/opt/vault-k8s-info.txt"

echo "🔍 Checking for ServiceAccount secret in namespace: ${NAMESPACE}"
if ! kubectl get secret "${SA_SECRET}" -n "${NAMESPACE}" &>/dev/null; then
  echo "❌ Secret ${SA_SECRET} not found in namespace ${NAMESPACE}."
  echo "Make sure Helm has deployed the vault-auth service account and token."
  exit 1
fi

echo "📡 Extracting Kubernetes API credentials..."
K8S_HOST=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
K8S_CA=$(kubectl get secret "${SA_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.ca\.crt}' | base64 --decode)
K8S_JWT=$(kubectl get secret "${SA_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.token}' | base64 --decode)

echo "💾 Writing credentials to ${OUTPUT_FILE}..."
sudo tee "${OUTPUT_FILE}" >/dev/null <<EOF
# Vault ↔ Kubernetes Integration (namespace: ${NAMESPACE})
K8S_HOST=${K8S_HOST}

# ---- Kubernetes CA Certificate ----
${K8S_CA}

# ---- Service Account JWT ----
${K8S_JWT}
EOF

sudo chmod 600 "${OUTPUT_FILE}"

echo "✅ Credentials saved to: ${OUTPUT_FILE}"
echo "Use this file when configuring Vault's Kubernetes Auth method."
