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
CHART_PKG="${CHART_DIR}/${APP_NAME}-chart.tgz"

# ======================================================
# STEP 1: CLEANUP
# ======================================================
echo "🧹 Cleaning previous build artifacts..."
rm -rf target/ "${CHART_PKG}" || true

if [[ ! -f .helmignore ]]; then
  cat <<EOF > .helmignore
target/
*.jar
*.tgz
*.log
*.iml
.idea/
.git/
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
# STEP 3: DOCKER IMAGE BUILD & PUSH
# ======================================================
echo "🐳 Building Docker image..."
NEW_DIGEST=$(sha256sum "target/${APP_NAME}-1.0.0.jar" | awk '{print $1}')
OLD_DIGEST=$(docker inspect "$IMAGE_FULL" --format '{{ index .Config.Labels "build_digest" }}' 2>/dev/null || echo "")

if [[ "$NEW_DIGEST" == "$OLD_DIGEST" ]]; then
  echo "🟢 Image already up-to-date. Skipping rebuild."
else
  docker build -t "$IMAGE_FULL" --label "build_digest=${NEW_DIGEST}" .
fi

echo "🔐 Ensuring Docker Hub login..."
if ! docker info >/dev/null 2>&1; then
  docker login docker.io
fi

echo "🚀 Pushing image to Docker Hub..."
docker push "$IMAGE_FULL"

# ======================================================
# STEP 4: PACKAGE HELM CHART
# ======================================================
echo "📦 Packaging Helm chart..."
helm lint "${CHART_DIR}" || true
helm dependency update "${CHART_DIR}" >/dev/null 2>&1 || true
helm package "${CHART_DIR}" -d "${CHART_DIR}"

# ======================================================
# STEP 5: INSTALL INGRESS
# ======================================================
echo "🌐 Enabling ingress controller..."
minikube addons enable ingress >/dev/null 2>&1 || true

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || true

# ======================================================
# STEP 6: DEPLOY USING PACKAGED CHART
# ======================================================
MINIKUBE_IP=$(minikube ip)
INGRESS_HOST="${MINIKUBE_IP}.nip.io"

echo "🚀 Installing Helm release..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE_NAME" "${CHART_PKG}" \
  --namespace "$NAMESPACE" \
  --set image.repository="docker.io/${DOCKER_USER}/${APP_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host="${INGRESS_HOST}" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --history-max 1 \
  --atomic \
  --wait

# ======================================================
# STEP 7: SUCCESS
# ======================================================
echo "🌍 Initial deployment complete!"
echo "✅ Access your app at: http://${INGRESS_HOST}"

# ======================================================
# STEP 8: HAND OFF TO REDEPLOY SCRIPT
# ======================================================
if [[ -x ./redeploy.sh ]]; then
  echo "🔁 Setup complete. You can now use ./redeploy.sh for future updates."
else
  echo "💡 Tip: Create redeploy.sh for faster updates next time!"
fi
