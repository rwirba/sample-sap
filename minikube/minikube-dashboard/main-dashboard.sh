#!/bin/bash
set -euo pipefail

# ==============================================================
# 🚀 Deploy Kubernetes Dashboard (GCR mirrors, demo namespace)
#      - Works with Minikube (Podman/CRI-O)
#      - Uses Cloudflare Tunnel for external access
# ==============================================================

DOMAIN="ryandemolab.app"
NAMESPACE="demo"
APP_NAME="kubernetes-dashboard"
TUNNEL_NAME="dashboard-tunnel"
LOCAL_CF_DIR="/home/ec2-user/.cloudflared"
S3_BUCKET="ryandevlab-bucket"
S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels/${TUNNEL_NAME}.json"

echo "🚀 Starting deployment for ${APP_NAME} in namespace '${NAMESPACE}'..."

# --- Ensure Minikube is running ---
if ! minikube status | grep -q "host: Running"; then
  echo "🧩 Starting Minikube with optimal resources..."
  HOST_CPUS=$(nproc)
  HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')  # MB
  REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
  REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

  echo "🧠 Host: ${HOST_CPUS} CPUs / ${HOST_MEM}MB RAM → Using ${REQ_CPUS} CPUs / ${REQ_MEM}MB"
  minikube start \
    --driver=podman \
    --container-runtime=cri-o \
    --mount=true \
    --mount-string="/data/minikube:/var/lib/minikube" \
    --cpus="${REQ_CPUS}" \
    --memory="${REQ_MEM}" \
    --disk-size=50g \
    --force
else
  echo "✅ Minikube already running."
fi

kubectl wait --for=condition=Ready node --all --timeout=180s || true

# --- Enable Ingress ---
if ! kubectl get ns ingress-nginx &>/dev/null; then
  echo "🧩 Enabling ingress controller..."
  minikube addons enable ingress
fi
kubectl wait -n ingress-nginx --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s || true

# --- Add official dashboard repo ---
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ >/dev/null
helm repo update >/dev/null

# --- Pre-pull dashboard images (avoid ImageInspectError) ---
echo "📦 Pre-pulling GCR dashboard images..."
for img in \
  gcr.io/k8s-minikube/kubernetes-dashboard:v2.7.0 \
  gcr.io/k8s-minikube/metrics-scraper:v1.0.8; do
  if ! minikube image ls | grep -q "$img"; then
    echo "⬇️  Pulling $img ..."
    minikube image pull "$img" || echo "⚠️  Could not pull $img, continuing..."
  else
    echo "✅ $img already present."
  fi
done

# --- Deploy Dashboard ---
echo "🧩 Deploying Dashboard via Helm..."
helm upgrade --install ${APP_NAME} kubernetes-dashboard/kubernetes-dashboard \
  --namespace ${NAMESPACE} --create-namespace \
  --set fullnameOverride="kubernetes-dashboard" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host="dashboard.${DOMAIN}" \
  --set service.type=ClusterIP \
  --set service.port=443 \
  --set service.targetPort=8443 \
  --set image.repository=gcr.io/k8s-minikube/kubernetes-dashboard \
  --set image.tag=v2.7.0 \
  --set metricsScraper.repository=gcr.io/k8s-minikube/metrics-scraper \
  --set metricsScraper.tag=v1.0.8 \
  --atomic --timeout 5m

# --- Wait for pods to be ready ---
echo "⏳ Waiting for Dashboard pods..."
kubectl wait --for=condition=Ready pod -l k8s-app=kubernetes-dashboard -n ${NAMESPACE} --timeout=180s || true

# --- Create admin-user account ---
echo "🔐 Ensuring admin-user ServiceAccount and binding..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: ${NAMESPACE}
EOF

# --- Generate admin token ---
TOKEN=$(kubectl -n ${NAMESPACE} create token admin-user)
echo "✅ Admin token generated successfully."
sudo mkdir -p /etc/minikube
echo "${TOKEN}" | sudo tee /etc/minikube/dashboard-token.txt >/dev/null
sudo chmod 600 /etc/minikube/dashboard-token.txt

# --- Cloudflare setup ---
echo "🌐 Setting up Cloudflare tunnel for ${DOMAIN}..."
mkdir -p "${LOCAL_CF_DIR}"
if [[ ! -f "${LOCAL_CF_DIR}/${TUNNEL_NAME}.json" ]]; then
  if aws s3 ls "${S3_TUNNEL_PATH}" >/dev/null 2>&1; then
    echo "⬇️  Found existing tunnel in S3. Downloading..."
    aws s3 cp "${S3_TUNNEL_PATH}" "${LOCAL_CF_DIR}/${TUNNEL_NAME}.json" --quiet
  else
    echo "🌐 Creating new Cloudflare tunnel..."
    cloudflared tunnel create "${TUNNEL_NAME}"
    aws s3 cp "${LOCAL_CF_DIR}/${TUNNEL_NAME}.json" "${S3_TUNNEL_PATH}" --quiet || true
  fi
fi

# --- Create Cloudflare config file ---
cat <<EOF > "${LOCAL_CF_DIR}/config.yml"
tunnel: ${TUNNEL_NAME}
credentials-file: ${LOCAL_CF_DIR}/${TUNNEL_NAME}.json
ingress:
  - hostname: dashboard.${DOMAIN}
    service: http://localhost:80
  - service: http_status:404
EOF

# --- Create systemd service for tunnel ---
sudo tee /etc/systemd/system/cloudflared-dashboard.service >/dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel for Kubernetes Dashboard
After=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel run ${TUNNEL_NAME}
Restart=always
User=ec2-user

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-dashboard.service

# --- Output summary ---
echo ""
echo "🎯 Deployment complete!"
echo "🌐 Access Dashboard: https://dashboard.${DOMAIN}"
echo "🔑 Token saved: /etc/minikube/dashboard-token.txt"
echo "☁️ Tunnel credentials synced with: ${S3_TUNNEL_PATH}"
echo ""
