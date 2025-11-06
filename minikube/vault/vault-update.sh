#!/bin/bash
set -euo pipefail

APP_NAME="vault-demo"
NAMESPACE="vault"
JOB_NAME="vault-k8s-bootstrap"

echo "🔁 Updating Vault deployment..."

# Step 1: Delete any old bootstrap job (immutable)
echo "🧹 Cleaning up old Vault bootstrap job..."
kubectl delete job "${JOB_NAME}" -n "${NAMESPACE}" --ignore-not-found

# Step 2: Run Helm upgrade (will recreate the job)
helm upgrade "${APP_NAME}" ./vault-chart \
  --namespace "${NAMESPACE}" \
  --install --atomic --timeout 5m

# Step 3: Wait for deployment rollout
kubectl rollout status deployment "${APP_NAME}" -n "${NAMESPACE}" || true

echo "✅ Vault successfully updated."
