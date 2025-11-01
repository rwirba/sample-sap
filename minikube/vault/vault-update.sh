#!/bin/bash
set -euo pipefail

APP_NAME="vault-demo"
NAMESPACE="vault"

echo "🔁 Updating Vault deployment..."

helm upgrade "${APP_NAME}" ./vault-chart --namespace "${NAMESPACE}" --wait

kubectl rollout status deployment "${APP_NAME}" -n "${NAMESPACE}"

echo "✅ Vault updated successfully!"
