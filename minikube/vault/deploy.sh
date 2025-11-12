#!/bin/bash
set -euo pipefail

APP_NAME="vault-demo"
CHART_PATH="./vault-chart"
NAMESPACE="demo"

echo "🚀 Deploying HashiCorp Vault (namespace: ${NAMESPACE})..."

# --- Ensure namespace exists ---
if ! kubectl get ns "${NAMESPACE}" &>/dev/null; then
  echo "🧱 Creating namespace ${NAMESPACE}..."
  kubectl create ns "${NAMESPACE}"
else
  echo "✅ Namespace ${NAMESPACE} already exists"
fi

# --- Deploy or upgrade Vault Helm chart ---
helm upgrade --install "${APP_NAME}" "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --wait

## --- Wait for Vault pod ---
echo "⏳ Waiting for Vault pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=vault-demo -n "${NAMESPACE}" --timeout=180s

VAULT_POD=$(kubectl get pod -n "${NAMESPACE}" -l app=vault-demo -o jsonpath="{.items[0].metadata.name}")
echo "✅ Vault pod detected: ${VAULT_POD}"

# --- Create service account if missing ---
if ! kubectl get sa vault-auth -n "${NAMESPACE}" &>/dev/null; then
  echo "🛠 Creating service account vault-auth..."
  cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
EOF
else
  echo "✅ Service account vault-auth already exists"
fi

# --- Check if Vault is initialized ---
echo "🔐 Checking Vault initialization status..."
INIT_STATUS=$(kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- vault status -format=json | jq -r .initialized || true)

if [[ "$INIT_STATUS" == "false" ]]; then
  echo "⚙️ Initializing Vault..."
  kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- vault operator init -key-shares=1 -key-threshold=1 > /tmp/vault-init.txt
  UNSEAL_KEY=$(grep 'Unseal Key 1:' /tmp/vault-init.txt | awk '{print $NF}')
  ROOT_TOKEN=$(grep 'Initial Root Token:' /tmp/vault-init.txt | awk '{print $NF}')
  echo "Vault initialized with root token and unseal key."
  kubectl create secret generic vault-init-keys -n "${NAMESPACE}" \
    --from-literal=unseal_key="${UNSEAL_KEY}" \
    --from-literal=root_token="${ROOT_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- vault operator unseal "${UNSEAL_KEY}"
else
  echo "✅ Vault already initialized."
fi

# --- Verify Vault unseal status ---
SEALED=$(kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- vault status -format=json | jq -r .sealed)
if [[ "$SEALED" == "true" ]]; then
  echo "🔓 Unsealing Vault using stored key..."
  UNSEAL_KEY=$(kubectl get secret vault-init-keys -n "${NAMESPACE}" -o jsonpath='{.data.unseal_key}' | base64 --decode)
  kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- vault operator unseal "${UNSEAL_KEY}"
else
  echo "✅ Vault is already unsealed."
fi

# --- Configure Vault using root token ---
ROOT_TOKEN=$(kubectl get secret vault-init-keys -n "${NAMESPACE}" -o jsonpath='{.data.root_token}' | base64 --decode)
echo "🔧 Configuring Vault using ROOT_TOKEN=${ROOT_TOKEN:0:6}******"

# Enable KV v2 secrets engine
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c "
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=${ROOT_TOKEN}
if ! vault secrets list | grep -q 'kv/'; then
  vault secrets enable -path=kv -version=2 kv
  echo '✅ Enabled KV v2 secrets engine'
else
  echo '✅ KV v2 already enabled'
fi
"

# Enable Kubernetes Auth
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c "
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=${ROOT_TOKEN}
if ! vault auth list | grep -q 'kubernetes/'; then
  vault auth enable kubernetes
  echo '✅ Enabled Kubernetes Auth'
else
  echo '✅ Kubernetes Auth already enabled'
fi
"

# Configure Kubernetes Auth method
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c "
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=${ROOT_TOKEN}
vault write auth/kubernetes/config \
  token_reviewer_jwt=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
  kubernetes_host=\"https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}\" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt >/dev/null
echo '✅ Kubernetes Auth configured'
"

# Create policy & role for HANA
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c "
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=${ROOT_TOKEN}
vault policy write hana-policy - <<EOF
path \"kv/data/hana\" {
  capabilities = [\"read\"]
}
EOF

if vault read auth/kubernetes/role/hana-role >/dev/null 2>&1; then
  echo '✅ Vault role hana-role already exists'
else
  vault write auth/kubernetes/role/hana-role \
    bound_service_account_names=vault-auth \
    bound_service_account_namespaces=${NAMESPACE} \
    policies=hana-policy \
    ttl=1h
  echo '✅ Vault role hana-role created'
fi
"

# --- Final status summary ---
echo "📊 Deployment Summary:"
kubectl get pods,svc,ingress -n "${NAMESPACE}"

echo "🎯 Vault successfully deployed and configured."
echo "🌐 Access the Vault UI at: https://vault.ryandemolab.app"
echo "🔑 Root token: ${ROOT_TOKEN}"
