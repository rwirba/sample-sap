#!/bin/bash
set -e

IMAGE_NAME="java-ads-demo"
IMAGE_TAG="1.0.0"
DOCKERHUB_USER="ryandevlab"

echo "Building Podman image: ${DOCKERHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG}..."

# Build the image using your Dockerfile
podman build -t docker.io/${DOCKERHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG} .

echo "🔐 Logging into Docker Hub..."
podman login docker.io --username ${DOCKERHUB_USER}

echo "Pushing image to Docker Hub..."
podman push docker.io/${DOCKERHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG}

echo "Image pushed successfully: ${DOCKERHUB_USER}/${IMAGE_NAME}:${IMAGE_TAG}"