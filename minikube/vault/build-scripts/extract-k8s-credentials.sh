#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# Extract Kubernetes credentials for Vault integration
# Saves: vault-k8s-info.txt (contains HOST, CA, JWT)
# -------------------------------------------------------------------

NAMESPACE="vault"
SA_SECRET="vault-auth-token"
OUTPUT_FILE="/opt/vault-k8s-info.txt"

echo "🔍 Checking for service account and secret..."
if ! kubectl get secret "${SA_SECRET}" -n "${NAMESPACE}" &>/dev/null; then
  echo "❌ Secret ${SA_SECRET} not found. Make sure vault-chart was deployed first."
  exit 1
fi

echo "📡 Extracting data for Vault Kubernetes config..."
K8S_HOST=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
K8S_CA=$(kubectl get secret "${SA_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.ca\.crt}' | base64 --decode)
K8S_JWT=$(kubectl get secret "${SA_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.token}' | base64 --decode)

echo "💾 Writing to ${OUTPUT_FILE}..."
sudo tee "${OUTPUT_FILE}" >/dev/null <<EOF
# -------------------------------
# Vault ↔ Kubernetes Integration
# -------------------------------
K8S_HOST=${K8S_HOST}

# ---- Kubernetes CA Certificate ----
${K8S_CA}

# ---- Service Account JWT ----
${K8S_JWT}
EOF

sudo chmod 600 "${OUTPUT_FILE}"

echo "✅ File saved: ${OUTPUT_FILE}"
echo "You can now open Vault UI → Access → Auth Methods → Kubernetes"
echo "Paste values from:"
echo "  • Kubernetes Host  → ${K8S_HOST}"
echo "  • Kubernetes CA Cert → (from file section)"
echo "  • Token Reviewer JWT → (from file section)"
