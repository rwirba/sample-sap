#!/usr/bin/env bash
set -euo pipefail

# Config
BUILD_DIR="${BUILD_DIR:-$(pwd)/hello-world}"
IMAGE_NAME="${IMAGE_NAME:-hello-world}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "[hello-world] Building Nginx-based Hello World image: ${LOCAL_IMAGE}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"


echo "[hello-world] Building image locally with Podman..."
podman build -t "${LOCAL_IMAGE}" .

echo "[hello-world] Loading image into Minikube..."
minikube image load "${LOCAL_IMAGE}"

echo "[hello-world] Done. Image is ready for Helm deployment: ${LOCAL_IMAGE}"