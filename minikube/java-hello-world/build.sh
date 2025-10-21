#!/bin/bash
set -euo pipefail

# ======================================================
# CONFIGURATION
# ======================================================
APP_NAME="java-hello-world"
DOCKER_USER="ryandevlab"
IMAGE_TAG="1.0.0"
IMAGE_FULL="docker.io/${DOCKER_USER}/${APP_NAME}:${IMAGE_TAG}"
NAMESPACE="demo-ns"
RELEASE_NAME="java-hello"
CHART_DIR="$(pwd)"

# ======================================================
# STEP 1: CLEANUP
# ======================================================
echo "🧹 Cleaning previous build artifacts..."
rm -rf target/ java-hello-world-*.tgz || true

if [[ ! -f .helmignore ]]; then
  cat <<EOF > .helmignore
target/
*.jar
*.tgz
*.log
*.iml
.idea/
.DS_Store
EOF
  echo "🛡️  Created .helmignore to exclude build artifacts."
fi

# ======================================================
# STEP 2: MAVEN BUILD
# ======================================================
echo "🔧 Building Java application..."
mvn clean package -DskipTests

# ======================================================
# STEP 3: PODMAN IMAGE BUILD
# ======================================================
echo "🐳 Building Podman image..."
NEW_DIGEST=$(sha256sum "target/${APP_NAME}-1.0.0.jar" | awk '{print $1}')
OLD_DIGEST=$(podman inspect "$IMAGE_FULL" --format '{{ index .Config.Labels "build_digest" }}' 2>/dev/null || echo "")

if [[ "$NEW_DIGEST" == "$OLD_DIGEST" ]]; then
  echo "🟢 Image already up-to-date. Skipping rebuild."
else
  podman build -t "$IMAGE_FULL" --label "build_digest=${NEW_DIGEST}" .
fi

# ======================================================
# STEP 4: LOGIN + PUSH
# ======================================================
echo "🔐 Ensuring Docker Hub login..."
if ! podman login --get-login docker.io >/dev/null 2>&1; then
  podman login docker.io
else
  echo "🟢 Already logged in to Docker Hub."
fi

echo "🚀 Pushing image to Docker Hub..."
podman push "$IMAGE_FULL" >/dev/null || true

# ======================================================
# STEP 5: ENSURE NGINX INGRESS CONTROLLER
# ======================================================
echo "🌐 Ensuring NGINX Ingress Controller is available..."

# Check if an IngressClass named "nginx" already exists
if kubectl get ingressclass nginx >/dev/null 2>&1; then
  echo "🟢 Existing NGINX IngressClass found — skipping Helm installation."
else
  # Add Helm repo if not present
  if ! helm repo list | grep -q "ingress-nginx"; then
    echo "📦 Adding ingress-nginx repo..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
  fi

  # Install via Helm if not already installed
  if ! helm status ingress-nginx -n ingress-nginx >/dev/null 2>&1; then
    echo "🚀 Installing ingress-nginx controller via Helm..."
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      -n ingress-nginx --create-namespace \
      --set controller.service.type=NodePort \
      --set controller.config.use-forwarded-headers=true \
      --wait
  else
    echo "🟢 ingress-nginx Helm release already present."
  fi
fi

# ======================================================
# STEP 6: DEPLOY APPLICATION VIA HELM
# ======================================================
echo "📦 Deploying Helm chart..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set image.repository="docker.io/${DOCKER_USER}/${APP_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host="hello.local" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --history-max 1 \
  --atomic \
  --wait

echo "⏳ Waiting for rollout..."
kubectl -n "$NAMESPACE" rollout status deployment/"${RELEASE_NAME}-${APP_NAME}" --timeout=180s

# ======================================================
# STEP 7: DISPLAY ACCESS INFO
# ======================================================
echo "🌍 Deployment successful!"

NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || echo "")
EC2_IP=$(curl -s http://checkip.amazonaws.com || hostname -I | awk '{print $1}')

if [[ -n "$NODEPORT" && -n "$EC2_IP" ]]; then
  echo "🌐 Access your app at:  http://${EC2_IP}:${NODEPORT}"
  echo "⚙️  Ensure TCP port ${NODEPORT} is open in your EC2 Security Group."
else
  echo "⚠️  Could not detect NodePort or public IP automatically."
  echo "🔎 Run manually: kubectl get svc -n ingress-nginx"
fi
