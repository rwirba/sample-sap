#!/bin/bash

set -e

APP_NAME="java-hello-world"
DOCKER_USER="ryandevlab"
IMAGE_TAG="1.0.0"
JAR_NAME="java-hello-world-1.0.0.jar"

echo "🔧 Building Java app with Maven..."
mvn clean package

echo "🐳 Building Podman image..."
podman build -t docker.io/$DOCKER_USER/$APP_NAME:$IMAGE_TAG .

echo "🔐 Logging into Docker Hub..."
podman login docker.io

echo "🚀 Pushing image to Docker Hub..."
podman push docker.io/$DOCKER_USER/$APP_NAME:$IMAGE_TAG

echo "✅ Done! Image pushed as $DOCKER_USER/$APP_NAME:$IMAGE_TAG"