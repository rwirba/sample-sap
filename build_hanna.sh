#!/usr/bin/env bash
set -euo pipefail

# Mode notes:
# - "standin" builds a Postgres-based HANA stand-in image.
# - "express-pull" pulls SAP HANA Express and retags it for ACR.

MODE="${MODE:-standin}"  # "standin" (default) or "express-pull"
BUILD_DIR="${BUILD_DIR:-/workspace/hana-standin}"
IMAGE_NAME="${IMAGE_NAME:-hana-standin}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
ACR_NAME="aksdemoacr3"
ACR_REPO="demo/${IMAGE_NAME}"
ACR_IMAGE="${ACR_NAME}.azurecr.io/${ACR_REPO}:${IMAGE_TAG}"

if [[ "$MODE" == "standin" ]]; then
  echo "[hana-standin] Building Postgres-based stand-in image: ${IMAGE_NAME}:${IMAGE_TAG}"
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"

  # Dockerfile
  cat > Dockerfile <<'EOF'
FROM docker.io/library/postgres:16
LABEL org.opencontainers.image.title="hana-standin" \
      org.opencontainers.image.description="PostgreSQL-based stand-in to demo StatefulSet/PVC in place of SAP HANA" \
      org.opencontainers.image.vendor="demo"
EXPOSE 5432
# COPY initdb/* /docker-entrypoint-initdb.d/
EOF

  # Optional init script
  mkdir -p initdb
  cat > initdb/001-demo.sql <<'EOF'
CREATE TABLE IF NOT EXISTS demo_hello(id SERIAL PRIMARY KEY, msg TEXT);
INSERT INTO demo_hello(msg) VALUES ('hello from hana-standin');
EOF

  echo "[hana-standin] Building image..."
  podman build --platform linux/amd64 -t "${IMAGE_NAME}:${IMAGE_TAG}" .

  echo "[hana-standin] Tagging for ACR..."
  podman tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ACR_IMAGE}"

  echo "[hana-standin] Pushing to ACR..."
  podman push "${ACR_IMAGE}"

  echo "[hana-standin] ✅ Done. Image pushed to: ${ACR_IMAGE}"
  echo "[hana-standin] You can run manually with: podman run -p 39013:5432 ${IMAGE_NAME}:${IMAGE_TAG}"
  exit 0
fi

if [[ "$MODE" == "express-pull" ]]; then
  HXE_IMAGE="${HXE_IMAGE:-saplabs/hanaexpress:2.00.061.00.20220519.1}"
  LOCAL_TAG="${LOCAL_TAG:-hana-express:2.00.061}"
  ACR_REPO="demo/${LOCAL_TAG}"
  ACR_IMAGE="${ACR_NAME}.azurecr.io/${ACR_REPO}"

  echo "[hana-express] Pulling ${HXE_IMAGE} (license/terms must be accepted)"
  podman pull "${HXE_IMAGE}"

  echo "[hana-express] Retagging as ${LOCAL_TAG}"
  podman tag "${HXE_IMAGE}" "${LOCAL_TAG}"
  podman tag "${LOCAL_TAG}" "${ACR_IMAGE}"

  echo "[hana-express] Pushing to ACR..."
  podman push "${ACR_IMAGE}"

  echo "[hana-express] ✅ Done. Image pushed to: ${ACR_IMAGE}"
  exit 0
fi

echo "Usage: MODE=standin|express-pull build_hana_db_image.sh"
exit 1