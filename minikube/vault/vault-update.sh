#!/bin/bash
set -euo pipefail

APP_NAME="vault-demo"
NAMESPACE="demo"
JOB_NAME="vault-k8s-bootstrap"
TIMEOUT="15m"

echo "🔁 Updating Vault deployment in namespace ${NAMESPACE}..."

# --- Clean up old bootstrap job ---
echo "🧹 Cleaning up old Vault bootstrap job..."
kubectl delete job "${JOB_NAME}" -n "${NAMESPACE}" --ignore-not-found

# --- Upgrade or install Vault ---
echo "🚀 Running Helm upgrade..."
helm upgrade --install "${APP_NAME}" ./vault-chart \
  --namespace "${NAMESPACE}" \
  --atomic \
  --timeout "${TIMEOUT}" || {
    echo "❌ Helm upgrade timed out — checking pod status..."
    kubectl get pods -n "${NAMESPACE}" -o wide
    exit 1
  }

# --- Wait for main Vault deployment to roll out ---
echo "⏳ Waiting for Vault rollout..."
kubectl rollout status deployment "${APP_NAME}" -n "${NAMESPACE}" --timeout="${TIMEOUT}" || true

# --- Wait for injector (if exists) ---
if kubectl get deploy -n "${NAMESPACE}" vault-agent-injector &>/dev/null; then
  echo "⏳ Waiting for Vault Agent Injector to be ready..."
  kubectl rollout status deployment vault-agent-injector -n "${NAMESPACE}" --timeout="${TIMEOUT}" || true
else
  echo "ℹ️  No injector deployment detected (skipping wait)."
fi

echo "✅ Vault successfully updated and injector checked."
