# #!/bin/bash
# set -euo pipefail

# APP_NAME="vault"
# CHART_PATH="./vault-chart"
# NAMESPACE="demo"

# echo "🚀 Deploying Vault to Minikube..."

# # Create namespace if missing
# kubectl get ns "${NAMESPACE}" &>/dev/null || kubectl create ns "${NAMESPACE}"

# # Deploy Helm chart
# helm upgrade --install vault-demo "${CHART_PATH}" \
#   --namespace "${NAMESPACE}" \
#   --wait

# # Wait for pod readiness
# echo "⏳ Waiting for Vault pod to be ready..."
# kubectl wait --for=condition=Ready pod -l app=vault-demo -n "${NAMESPACE}" --timeout=180s

# # Show service details
# echo "✅ Vault deployed successfully!"
# kubectl get pods,svc,ingress -n "${NAMESPACE}"

# #

#!/bin/bash
set -euo pipefail

APP_NAME="vault"
CHART_PATH="./vault-chart"
NAMESPACE="demo"
SERVICE_ACCOUNT="vault-auth"
ROLE_NAME="hana-role"
POLICY_NAME="hana-read"
SECRET_PATH="kv/hana"

echo "🚀 Deploying Vault to Minikube (namespace: ${NAMESPACE})..."

# ---------------------------------------------------------------------
# 1️⃣  Namespace setup
# ---------------------------------------------------------------------
if ! kubectl get ns "${NAMESPACE}" &>/dev/null; then
  kubectl create ns "${NAMESPACE}"
  echo "✅ Created namespace ${NAMESPACE}"
else
  echo "ℹ️  Namespace ${NAMESPACE} already exists"
fi

# ---------------------------------------------------------------------
# 2️⃣  Deploy Vault Helm chart (with injector enabled)
# ---------------------------------------------------------------------
helm upgrade --install vault-demo "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --set injector.enabled=true \
  --wait --atomic

# ---------------------------------------------------------------------
# 3️⃣  Wait until Vault pod is ready
# ---------------------------------------------------------------------
echo "⏳ Waiting for Vault pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=vault-demo -n "${NAMESPACE}" --timeout=300s

VAULT_POD=$(kubectl get pod -n "${NAMESPACE}" -l app=vault-demo -o jsonpath='{.items[0].metadata.name}')
echo "✅ Vault pod detected: ${VAULT_POD}"

# ---------------------------------------------------------------------
# 4️⃣  Ensure service account exists
# ---------------------------------------------------------------------
if ! kubectl get sa "${SERVICE_ACCOUNT}" -n "${NAMESPACE}" &>/dev/null; then
  kubectl create sa "${SERVICE_ACCOUNT}" -n "${NAMESPACE}"
  echo "✅ Created service account ${SERVICE_ACCOUNT}"
else
  echo "ℹ️  Service account ${SERVICE_ACCOUNT} already exists"
fi

# ---------------------------------------------------------------------
# 5️⃣  Enable KV secrets engine (do NOT create secret)
# ---------------------------------------------------------------------
echo "🔐 Ensuring KV v2 secrets engine is enabled..."
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
vault secrets list | grep -q "kv/" || vault secrets enable -path=kv -version=2 kv
'

echo "🗝️  Skipping secret creation — please create it manually:"
echo "    vault kv put kv/hana master_password=<YOUR_PASSWORD>"
echo

# ---------------------------------------------------------------------
# 6️⃣  Create/update read policy (idempotent)
# ---------------------------------------------------------------------
echo "📜 Creating or updating Vault policy..."
cat <<'EOF' | kubectl exec -i -n "${NAMESPACE}" "${VAULT_POD}" -- tee /tmp/hana-read.hcl >/dev/null
path "kv/data/hana" {
  capabilities = ["read"]
}
EOF

kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
vault policy write '"${POLICY_NAME}"' /tmp/hana-read.hcl >/dev/null
'

# ---------------------------------------------------------------------
# 7️⃣  Enable & configure Kubernetes auth method (idempotent)
# ---------------------------------------------------------------------
echo "⚙️  Configuring Kubernetes auth method..."
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
vault auth list | grep -q "kubernetes/" || vault auth enable kubernetes
vault write auth/kubernetes/config \
  token_reviewer_jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
  kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt >/dev/null
'

# ---------------------------------------------------------------------
# 8️⃣  Create/update Vault role (idempotent)
# ---------------------------------------------------------------------
echo "🔧 Creating or updating Vault role..."
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
vault write auth/kubernetes/role/'"${ROLE_NAME}"' \
  bound_service_account_names='"${SERVICE_ACCOUNT}"' \
  bound_service_account_namespaces='"${NAMESPACE}"' \
  policies='"${POLICY_NAME}"' \
  ttl="1h" >/dev/null
'

# ---------------------------------------------------------------------
# 9️⃣  Final verification
# ---------------------------------------------------------------------
echo
echo "✅ Vault deployment and configuration complete!"
kubectl get pods,svc,ingress -n "${NAMESPACE}" -o wide

echo
echo "🔍 Verifying role and injector..."
kubectl get pod -n "${NAMESPACE}" | grep injector || echo "⚠️ Injector pod not visible yet (still starting)."
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- vault read -format=json auth/kubernetes/role/${ROLE_NAME} | jq '.data' || true

echo
echo "🎉 Vault is ready for secure secret injection"
echo "------------------------------------------------------------"
echo "🪣 Namespace: ${NAMESPACE}"
echo "👤 Service Account: ${SERVICE_ACCOUNT}"
echo "🔐 Role: ${ROLE_NAME}"
echo "📜 Policy: ${POLICY_NAME}"
echo "📂 Secret Path: ${SECRET_PATH}"
echo "------------------------------------------------------------"
echo
echo "Next step: manually create your secret inside Vault:"
echo "vault kv put kv/hana master_password=<YOUR_PASSWORD>"
echo
echo "Once done, redeploy your HANA StatefulSet — Vault injector will automatically inject the secret."
