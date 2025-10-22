#!/bin/bash
set -euo pipefail

APP_NAME="java-hello-world"
DOCKER_USER="ryandevlab"
IMAGE_TAG="1.0.0"
IMAGE_FULL="docker.io/${DOCKER_USER}/${APP_NAME}:${IMAGE_TAG}"
NAMESPACE="demo-ns"
RELEASE_NAME="java-hello"
CHART_DIR="$(pwd)"
CHART_PKG="${CHART_DIR}/${APP_NAME}-chart.tgz"

echo "🔧 Building Java application..."
mvn clean package -DskipTests

echo "🐳 Building Docker image..."
NEW_DIGEST=$(sha256sum "target/${APP_NAME}-1.0.0.jar" | awk '{print $1}')
OLD_DIGEST=$(docker inspect "$IMAGE_FULL" --format '{{ index .Config.Labels "build_digest" }}' 2>/dev/null || echo "")

if [[ "$NEW_DIGEST" == "$OLD_DIGEST" ]]; then
  echo "🟢 Image already up-to-date. Skipping rebuild."
else
  docker build -t "$IMAGE_FULL" --label "build_digest=${NEW_DIGEST}" .
fi

echo "🔐 Checking Docker Hub login..."
CURRENT_USER=$(docker info --format '{{.AuthConfig.Username}}' 2>/dev/null || echo "")

if [[ "$CURRENT_USER" != "$DOCKER_USER" ]]; then
  echo "🔄 Logging in to Docker Hub as ${DOCKER_USER}..."
  echo "💡 Tip: If you use tokens, enter your personal access token as password."
  docker login docker.io -u "$DOCKER_USER"
else
  echo "🟢 Already logged in as ${DOCKER_USER}."
fi

echo "🚀 Pushing image to Docker Hub..."
docker push "$IMAGE_FULL"

echo "📦 Packaging Helm chart..."
rm -f ${CHART_DIR}/${APP_NAME}-*.tgz || true
helm package "${CHART_DIR}" -d "${CHART_DIR}"

# Automatically detect the packaged chart file
CHART_PKG=$(ls ${CHART_DIR}/${APP_NAME}-*.tgz | head -n 1)

MINIKUBE_IP=$(minikube ip)
INGRESS_HOST="${MINIKUBE_IP}.nip.io"

echo "🚀 Redeploying Helm release..."
helm upgrade --install "$RELEASE_NAME" "${CHART_PKG}" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set image.repository="docker.io/${DOCKER_USER}/${APP_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host="${INGRESS_HOST}" \
  --set ingress.hosts[0].paths[0].path="/" \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --atomic \
  --wait

kubectl -n "$NAMESPACE" rollout status deployment/"${RELEASE_NAME}-${APP_NAME}" --timeout=180s
echo "🌍 Deployment successful!"
echo "✅ Access your app at: http://${INGRESS_HOST}"
