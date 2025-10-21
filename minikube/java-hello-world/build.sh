#!/bin/bash
set -euo pipefail

# ========================
# CONFIGURATION
# ========================
APP_NAME="java-hello-world"
DOCKER_USER="ryandevlab"
IMAGE_TAG="1.0.0"
IMAGE_FULL="docker.io/${DOCKER_USER}/${APP_NAME}:${IMAGE_TAG}"
NAMESPACE="demo-ns"
RELEASE_NAME="java-hello"
WORK_DIR="$(pwd)"
CHART_DIR="${WORK_DIR}/chart-workdir"
HOST_ENTRY="hello.local"

# ========================
# SAFETY: ENSURE CLEAN WORKDIR
# ========================
if [[ "$WORK_DIR" =~ "/containers/storage" ]] || [[ "$WORK_DIR" =~ ".local/share/containers" ]]; then
  echo "⚠️  You are inside a Podman overlay storage path!"
  echo "   Copying chart to a safe working directory..."
  mkdir -p "$HOME/helm-safe"
  rsync -a --delete "$WORK_DIR/" "$CHART_DIR"
else
  CHART_DIR="$WORK_DIR"
fi

# ========================
# STEP 1: CLEANUP
# ========================
echo "🧹 Cleaning previous build artifacts..."
rm -rf "${CHART_DIR}/target/" "${CHART_DIR}"/java-hello-world-*.tgz || true

# Optional safety: ensure Helm won’t package junk
if [[ ! -f "${CHART_DIR}/.helmignore" ]]; then
  cat <<EOF > "${CHART_DIR}/.helmignore"
target/
*.jar
*.tgz
*.log
*.iml
.idea/
.DS_Store
EOF
  echo "🛡️  Created .helmignore to exclude build artifacts from Helm packages."
fi

# ========================
# STEP 2: MAVEN BUILD
# ========================
echo "🔧 Building Java application..."
cd "$CHART_DIR"
mvn clean package -DskipTests

# ========================
# STEP 3: PODMAN IMAGE BUILD
# ========================
echo "🐳 Building Podman image..."
NEW_DIGEST=$(sha256sum "target/${APP_NAME}-1.0.0.jar" | awk '{print $1}')
OLD_DIGEST=$(podman inspect "$IMAGE_FULL" --format '{{ index .Config.Labels "build_digest" }}' 2>/dev/null || echo "")

if [[ "$NEW_DIGEST" == "$OLD_DIGEST" ]]; then
  echo "🟢 Image already up-to-date. Skipping rebuild."
else
  podman build -t "$IMAGE_FULL" --label "build_digest=${NEW_DIGEST}" .
fi

# ========================
# STEP 4: LOGIN + PUSH
# ========================
echo "🔐 Ensuring Docker Hub login..."
if ! podman login --get-login docker.io >/dev/null 2>&1; then
  podman login docker.io
else
  echo "🟢 Already logged in to Docker Hub."
fi

echo "🚀 Pushing image to Docker Hub..."
podman push "$IMAGE_FULL" >/dev/null || true

# ========================
# STEP 5: HELM DEPLOYMENT
# ========================
echo "📦 Deploying Helm chart to Minikube..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set image.repository="docker.io/${DOCKER_USER}/${APP_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host="$HOST_ENTRY" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --history-max 1 \
  --atomic \
  --wait

# ========================
# STEP 6: WAIT FOR DEPLOYMENT
# ========================
echo "⏳ Waiting for deployment rollout..."
kubectl -n "$NAMESPACE" rollout status deployment/"${RELEASE_NAME}-${APP_NAME}" --timeout=180s

# ========================
# STEP 7: ENSURE INGRESS
# ========================
echo "🌐 Ensuring NGINX Ingress is enabled..."
minikube addons enable ingress >/dev/null 2>&1 || true

if ! pgrep -f "minikube tunnel" >/dev/null; then
  echo "🌀 Starting minikube tunnel..."
  nohup minikube tunnel >/dev/null 2>&1 &
else
  echo "🟢 Minikube tunnel already running."
fi

# ========================
# STEP 8: UPDATE /etc/hosts
# ========================
echo "🧭 Ensuring local DNS entry for ${HOST_ENTRY}..."
MINIKUBE_IP=$(minikube ip)
if ! grep -q "$HOST_ENTRY" /etc/hosts; then
  echo "$MINIKUBE_IP  $HOST_ENTRY" | sudo tee -a /etc/hosts >/dev/null
  echo "✅ Added $HOST_ENTRY -> $MINIKUBE_IP to /etc/hosts"
else
  echo "🟢 Host entry already present in /etc/hosts"
fi

# ========================
# STEP 9: ACCESS APP
# ========================
echo "🎉 Deployment complete!"
echo "➡️  Access your app at: http://${HOST_ENTRY}"

if command -v open >/dev/null; then
  open "http://${HOST_ENTRY}"
elif command -v xdg-open >/dev/null; then
  xdg-open "http://${HOST_ENTRY}"
fi
