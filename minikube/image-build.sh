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

# Dockerfile
cat > Dockerfile <<'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

# HTML content
cat > index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Hello World</title></head>
<body><h1>Hello from AKS Demo Session Presented By Ryan!</h1></body>
</html>
EOF

echo "[hello-world] Building image locally with Podman..."
podman build -t "${LOCAL_IMAGE}" .

echo "[hello-world] Loading image into Minikube..."
minikube image load "${LOCAL_IMAGE}"

echo "[hello-world] Done. Image is ready for Helm deployment: ${LOCAL_IMAGE}"