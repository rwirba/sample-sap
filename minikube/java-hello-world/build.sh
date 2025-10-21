#!/bin/bash
set -euo pipefail

# === Config ===
APP_NAME="java-hello-world"
DOCKER_USER="ryandevlab"
IMAGE_TAG="1.0.0"
IMAGE_FULL="docker.io/${DOCKER_USER}/${APP_NAME}:${IMAGE_TAG}"
NAMESPACE="demo-ns"
RELEASE_NAME="java-hello"
CHART_DIR="$(pwd)"
JAR_NAME="target/java-hello-world-1.0.0.jar"
HOST_ENTRY="hello.local"

echo "🔧 [1/8] Building Java JAR..."
mvn clean package -DskipTests

# Compute digest to detect change
NEW_DIGEST=$(sha256sum "$JAR_NAME" | awk '{print $1}')
OLD_DIGEST=$(podman inspect "$IMAGE_FULL" --format '{{ index .Config.Labels "build_digest" }}' 2>/dev/null || echo "")

if [[ "$NEW_DIGEST" == "$OLD_DIGEST" ]]; then
  echo "🟢 Existing image already built for current JAR. Skipping rebuild."
else
  echo "🐳 [2/8] Building Podman image..."
  podman build \
    -t "$IMAGE_FULL" \
    --label "build_digest=${NEW_DIGEST}" \
    .
fi

echo "🔐 [3/8] Ensuring Docker login session..."
if ! podman login --get-login docker.io >/dev/null 2>&1; then
  podman login docker.io
else
  echo "🟢 Already logged in to Docker Hub."
fi

echo "🚀 [4/8] Pushing image to Docker Hub (idempotent overwrite)..."
podman push "$IMAGE_FULL" >/dev/null || true

echo "📦 [5/8] Deploying Helm chart to Minikube..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set image.repository="docker.io/${DOCKER_USER}/${APP_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --wait

echo "⏳ [6/8] Waiting for deployment rollout..."
kubectl -n "$NAMESPACE" rollout status deployment/"${RELEASE_NAME}-${APP_NAME}" --timeout=120s

echo "🌐 [7/8] Ensuring Ingress and Minikube tunnel are active..."
minikube addons enable ingress >/dev/null 2>&1 || true

# Start tunnel if not already running
if ! pgrep -f "minikube tunnel" >/dev/null; then
  echo "🌀 Starting minikube tunnel..."
  nohup minikube tunnel >/dev/null 2>&1 &
else
  echo "🟢 Minikube tunnel already running."
fi

echo "🧭 [8/8] Ensuring local host entry for ${HOST_ENTRY}..."
MINIKUBE_IP=$(minikube ip)
if ! grep -q "$HOST_ENTRY" /etc/hosts; then
  echo "$MINIKUBE_IP  $HOST_ENTRY" | sudo tee -a /etc/hosts >/dev/null
  echo "✅ Added $HOST_ENTRY -> $MINIKUBE_IP to /etc/hosts"
else
  echo "🟢 Host entry already present in /etc/hosts"
fi

echo "🎉 Deployment complete!"
echo "➡️ Access your app at: http://$HOST_ENTRY"
