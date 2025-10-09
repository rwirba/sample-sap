#!/usr/bin/env bash
set -euo pipefail

# Mode notes:
# - "build" creates a Hello World image using Nginx + static HTML.
# - "pull" retags an existing image (e.g., nginx:alpine) for ACR use.

MODE="${MODE:-build}"  # "build" (default) or "pull"
BUILD_DIR="${BUILD_DIR:-/workspace/hello-world}"
IMAGE_NAME="${IMAGE_NAME:-hello-world}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ACR_NAME="aksdemoacr3"  # Your ACR name
ACR_REPO="${IMAGE_NAME}"  # Optional subpath in ACR

ACR_IMAGE="${ACR_NAME}.azurecr.io/${ACR_REPO}:${IMAGE_TAG}"

if [[ "$MODE" == "build" ]]; then
  echo "[hello-world] Building Nginx-based Hello World image: ${IMAGE_NAME}:${IMAGE_TAG}"
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"

  # Dockerfile
  cat > Dockerfile <<'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
EOF

  # HTML content
  cat > index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Hello World</title></head>
<body><h1>Hello from AKS Demo Session Presented By Ryan!</h1></body>
</html>
EOF

  echo "[hello-world] Building image..."
  podman build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

  echo "[hello-world] Tagging for ACR..."
  podman tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ACR_IMAGE}"

  echo "[hello-world] Pushing to ACR..."
  podman push "${ACR_IMAGE}"

  echo "[hello-world] Done. Image pushed to: ${ACR_IMAGE}"
  exit 0
fi

if [[ "$MODE" == "pull" ]]; then
  BASE_IMAGE="${BASE_IMAGE:-nginx:alpine}"
  LOCAL_TAG="${LOCAL_TAG:-hello-world:nginx}"

  echo "[hello-world] Pulling ${BASE_IMAGE}"
  podman pull "${BASE_IMAGE}"
  echo "[hello-world] Retagging as ${LOCAL_TAG}"
  podman tag "${BASE_IMAGE}" "${LOCAL_TAG}"
  podman tag "${LOCAL_TAG}" "${ACR_IMAGE}"

  echo "[hello-world] Pushing to ACR..."
  podman push "${ACR_IMAGE}"

  echo "[hello-world] Done. Image pushed to: ${ACR_IMAGE}"
  exit 0
fi

echo "Usage: MODE=build|pull build_hello_world_image.sh"
exit 1