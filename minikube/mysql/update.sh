#!/bin/bash
set -euo pipefail

IMAGE_NAME="mysql-demo"
TAG="latest"
DOCKER_USER="ryandevlab"

echo "♻️ Rebuilding MySQL image..."
podman build -t ${IMAGE_NAME}:${TAG} .
podman tag ${IMAGE_NAME}:${TAG} ${DOCKER_USER}/${IMAGE_NAME}:${TAG}
podman push ${DOCKER_USER}/${IMAGE_NAME}:${TAG}

echo "🔄 Restarting StatefulSet in cluster..."
kubectl rollout restart statefulset mysql-db -n demo

echo "✅ MySQL updated successfully."
