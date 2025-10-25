#!/bin/bash
set -euo pipefail

IMAGE_NAME="mysql-demo"
TAG="latest"
DOCKER_USER="ryandevlab"

echo "🐳 Building MySQL image..."
podman build -t ${IMAGE_NAME}:${TAG} .

echo "🔐 Logging into Docker Hub..."
podman login -u ${DOCKER_USER}

echo "🏷️ Tagging and pushing image..."
podman tag ${IMAGE_NAME}:${TAG} ${DOCKER_USER}/${IMAGE_NAME}:${TAG}
podman push ${DOCKER_USER}/${IMAGE_NAME}:${TAG}

echo "✅ MySQL image pushed to Docker Hub."
