#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Vault Image Build and Push Script
# Author: Ryan DevLab
# -------------------------------------------------------------------

DOCKER_USER="ryandevlab"
VAULT_IMAGE_NAME="${DOCKER_USER}/dev-vault:1.0.0"
DOCKERFILE_PATH="$(pwd)/Dockerfile"

# -------------------------------------------------------------------
# Validate Dockerfile
# -------------------------------------------------------------------
if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "[ERROR] Dockerfile not found in $(pwd)"
  exit 1
fi

# -------------------------------------------------------------------
# Build image
# -------------------------------------------------------------------
echo "[INFO] Building Vault image: ${VAULT_IMAGE_NAME}"
podman build -t "${VAULT_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" --format docker

# -------------------------------------------------------------------
# Authenticate & Push to Docker Hub
# -------------------------------------------------------------------
echo -n "Enter your Docker Hub password for ${DOCKER_USER}: "
read -rs DOCKER_PASS
echo
echo "${DOCKER_PASS}" | podman login -u "${DOCKER_USER}" --password-stdin docker.io

echo "[INFO] Pushing image to Docker Hub..."
podman push "${VAULT_IMAGE_NAME}"

# -------------------------------------------------------------------
# Verify push success
# -------------------------------------------------------------------
echo "[INFO] Checking pushed image..."
podman search "${VAULT_IMAGE_NAME%:*}" | grep "${VAULT_IMAGE_NAME##*:}" || \
  echo "[WARN] Could not verify image tag remotely (may be delayed)."

echo
echo "-------------------------------------------------------------"
echo "[✅ SUCCESS] Vault image built and pushed to Docker Hub!"
echo "Image: ${VAULT_IMAGE_NAME}"
echo "You can now deploy it with Minikube or Kubernetes."
echo "-------------------------------------------------------------"
