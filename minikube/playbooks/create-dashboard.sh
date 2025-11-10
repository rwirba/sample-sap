#!/bin/bash
set -euo pipefail

DOMAIN="{{ domain }}"
NAMESPACE="{{ namespace }}"
SECRET_NAME="{{ secret_name }}"
S3_BUCKET="{{ s3_bucket }}"
S3_CERT_PATH="s3://${S3_BUCKET}/origin.crt"
S3_KEY_PATH="s3://${S3_BUCKET}/origin.key"
DASHBOARD_TOKEN_PATH="{{ dashboard_token_path }}"

echo "🚀 Setting up Kubernetes Dashboard in namespace: ${NAMESPACE}"

# 1️⃣ Create namespace
kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"

# 2️⃣ Download TLS cert/key from S3
aws s3 cp "${S3_CERT_PATH}" /tmp/origin.crt --quiet
aws s3 cp "${S3_KEY_PATH}" /tmp/origin.key --quiet

# 3️⃣ Create TLS secret
kubectl -n "${NAMESPACE}" delete secret "${SECRET_NAME}" --ignore-not-found
kubectl -n "${NAMESPACE}" create secret tls "${SECRET_NAME}" \
  --cert=/tmp/origin.crt --key=/tmp/origin.key

# 4️⃣ Add Helm repo and update
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard
helm repo update

# 5️⃣ Deploy dashboard via Helm
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host="dashboard.${DOMAIN}" \
  --set service.type=ClusterIP \
  --set service.port=443 \
  --set service.targetPort=8443 \
  --atomic --timeout 900s

# 6️⃣ Apply admin-user RBAC
kubectl apply -n "${NAMESPACE}" -f /tmp/admin-user-rbac.yaml

# 7️⃣ Generate dashboard token
TOKEN=$(kubectl -n "${NAMESPACE}" create token admin-user --duration=24h)
echo "${TOKEN}" > "${DASHBOARD_TOKEN_PATH}"
chmod 0644 "${DASHBOARD_TOKEN_PATH}"

# 8️⃣ Upload token to S3
aws s3 cp "${DASHBOARD_TOKEN_PATH}" "s3://${S3_BUCKET}/dashboard-token.txt" --quiet

echo "✅ Dashboard setup complete!"
echo "🔑 Token saved at ${DASHBOARD_TOKEN_PATH}"
