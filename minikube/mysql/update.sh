#!/bin/bash
set -euo pipefail

IMAGE_NAME="mysql-demo"
TAG="latest"
DOCKER_USER="ryandevlab"

echo "♻️ Rebuilding MySQL image..."
podman build -t docker.io/${DOCKERHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG} .

echo "🔐 Logging into Docker Hub..."
podman login docker.io --username ${DOCKERHUB_USER}

echo "Pushing image to Docker Hub..."
podman push docker.io/${DOCKERHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG}

echo "🔄 Restarting StatefulSet in cluster..."
kubectl rollout restart statefulset mysql-db -n demo

echo "✅ MySQL updated successfully."
