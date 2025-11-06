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

APP_NAME="vault-demo"
CHART_PATH="./vault-chart"
NAMESPACE="demo"

echo "Deploying Vault to Minikube (namespace: ${NAMESPACE})..."

# --- Ensure namespace exists ---
if ! kubectl get ns "${NAMESPACE}" &>/dev/null; then
  echo "Creating namespace ${NAMESPACE}..."
  kubectl create ns "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists"
fi

# --- Deploy or upgrade Vault chart ---
helm upgrade --install "${APP_NAME}" "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --wait

echo "Waiting for Vault pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=vault-demo -n "${NAMESPACE}" --timeout=180s

# --- Capture the Vault pod name ---
VAULT_POD=$(kubectl get pod -n "${NAMESPACE}" -l app=vault-demo -o jsonpath="{.items[0].metadata.name}")
echo "Vault pod detected: ${VAULT_POD}"

# --- Ensure the service account exists ---
if ! kubectl get sa vault-auth -n "${NAMESPACE}" &>/dev/null; then
  echo "Creating service account: vault-auth"
  kubectl apply -f "${CHART_PATH}/templates/vault-k8s-auth.yaml" -n "${NAMESPACE}"
else
  echo "Service account vault-auth already exists"
fi

# --- Configure Vault internally ---
echo "Configuring Vault inside pod..."

# Enable KV v2 secrets engine (idempotent)
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
export VAULT_ADDR="http://127.0.0.1:8200"
if ! vault secrets list | grep -q "kv/"; then
  echo "Enabling KV v2 secrets engine..."
  vault secrets enable -path=kv -version=2 kv
else
  echo "KV v2 secrets engine already enabled"
fi
'

# Enable Kubernetes auth (idempotent)
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
export VAULT_ADDR="http://127.0.0.1:8200"
if ! vault auth list | grep -q "kubernetes/"; then
  echo "Enabling Kubernetes Auth..."
  vault auth enable kubernetes
else
  echo "Kubernetes Auth already enabled"
fi
'

# Configure Kubernetes Auth method
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
export VAULT_ADDR="http://127.0.0.1:8200"
echo "Configuring Kubernetes Auth..."
vault write auth/kubernetes/config \
  token_reviewer_jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
  kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt >/dev/null
echo "Kubernetes Auth configured"
'

# Create HANA policy (idempotent)
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
export VAULT_ADDR="http://127.0.0.1:8200"
echo "Ensuring Vault policy hana-policy..."
cat <<EOF | vault policy write hana-policy -
path "kv/data/hana" {
  capabilities = ["read"]
}
EOF
'

# Create Kubernetes role for HANA (idempotent)
kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- sh -c '
export VAULT_ADDR="http://127.0.0.1:8200"
if vault read auth/kubernetes/role/hana-role >/dev/null 2>&1; then
  echo "Vault role hana-role already exists"
else
  echo "Creating Vault role hana-role..."
  vault write auth/kubernetes/role/hana-role \
    bound_service_account_names=vault-auth \
    bound_service_account_namespaces='"${NAMESPACE}"' \
    policies=hana-policy \
    ttl=1h
  echo "Vault role hana-role created"
fi
'

# --- Final status summary ---
echo "Deployment Summary:"
kubectl get pods,svc,ingress -n "${NAMESPACE}"

echo "Vault successfully deployed and configured in namespace ${NAMESPACE}"
