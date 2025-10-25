#!/bin/bash
set -euo pipefail

IMAGE_NAME="mysql-demo"
TAG="latest"
DOCKER_USER="<your-dockerhub-username>"

echo "♻️ Rebuilding MySQL image..."
docker build -t ${IMAGE_NAME}:${TAG} .
docker tag ${IMAGE_NAME}:${TAG} ${DOCKER_USER}/${IMAGE_NAME}:${TAG}
docker push ${DOCKER_USER}/${IMAGE_NAME}:${TAG}

echo "🔄 Restarting StatefulSet in cluster..."
kubectl rollout restart statefulset mysql-db -n demo

echo "✅ MySQL updated successfully."
