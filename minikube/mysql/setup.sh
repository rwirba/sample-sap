#!/bin/bash
set -euo pipefail

IMAGE_NAME="mysql-demo"
TAG="latest"
DOCKER_USER="<your-dockerhub-username>"

echo "🐳 Building MySQL image..."
docker build -t ${IMAGE_NAME}:${TAG} .

echo "🔐 Logging into Docker Hub..."
docker login -u ${DOCKER_USER}

echo "🏷️ Tagging and pushing image..."
docker tag ${IMAGE_NAME}:${TAG} ${DOCKER_USER}/${IMAGE_NAME}:${TAG}
docker push ${DOCKER_USER}/${IMAGE_NAME}:${TAG}

echo "✅ MySQL image pushed to Docker Hub."
