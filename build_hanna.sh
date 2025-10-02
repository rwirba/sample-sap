# Save inside k1 (e.g., /usr/local/bin/build_hana_db_image.sh) and chmod +x it
#!/usr/bin/env bash
set -euo pipefail

# Mode notes:
# - Default builds a **HANA stand-in** image using Postgres (no SAP license needed).
# - If you later get access to SAP HANA, express edition (HXE), you can PULL+TAG it
#   for ACR with the commented section below (not a build).
MODE="${MODE:-standin}"  # "standin" (default) or "express-pull"

BUILD_DIR="${BUILD_DIR:-/workspace/hana-standin}"
IMAGE_NAME="${IMAGE_NAME:-hana-standin}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"

if [[ "$MODE" == "standin" ]]; then
  echo "[hana-standin] Building Postgres-based stand-in image: ${IMAGE_NAME}:${IMAGE_TAG}"
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"

  # Dockerfile: thin wrapper on Postgres so you tag/push as a 'hana-like' image
  cat > Dockerfile <<'EOF'
FROM docker.io/library/postgres:16
LABEL org.opencontainers.image.title="hana-standin" \
      org.opencontainers.image.description="PostgreSQL-based stand-in to demo StatefulSet/PVC in place of SAP HANA" \
      org.opencontainers.image.vendor="demo"
# Default Postgres port; when you RUN the container manually later, you can map -p 39013:5432 to mimic HANA-style ports.
EXPOSE 5432
# Optional: place init SQL here if you want demo tables
# COPY initdb/* /docker-entrypoint-initdb.d/
EOF

  # Optional init script example (uncomment COPY above if you want it)
  mkdir -p initdb
  cat > initdb/001-demo.sql <<'EOF'
-- demo schema you can remove/ignore
CREATE TABLE IF NOT EXISTS demo_hello(id SERIAL PRIMARY KEY, msg TEXT);
INSERT INTO demo_hello(msg) VALUES ('hello from hana-standin');
EOF

  echo "[hana-standin] Building image..."
  podman build --platform linux/amd64 -t "${IMAGE_NAME}:${IMAGE_TAG}" .

  echo "[hana-standin] Built image:"
  podman images | awk 'NR==1 || $1 ~ /'"${IMAGE_NAME}"'/'
  echo "[hana-standin] To push later: podman tag ${IMAGE_NAME}:${IMAGE_TAG} <ACR_NAME>.azurecr.io/demo/${IMAGE_NAME}:${IMAGE_TAG}"
  echo "[hana-standin] When running manually, you can mimic HANA port externally with: -p 39013:5432"
  exit 0
fi

if [[ "$MODE" == "express-pull" ]]; then
  # This does NOT build; it PULLS SAP HANA, express edition (HXE) and retags it.
  # Requires you to have accepted SAP's terms and have access to the image.
  HXE_IMAGE="${HXE_IMAGE:-saplabs/hanaexpress:2.00.061.00.20220519.1}"
  LOCAL_TAG="${LOCAL_TAG:-hana-express:2.00.061}"

  echo "[hana-express] Pulling ${HXE_IMAGE} (license/terms must be accepted in your account)"
  podman pull "${HXE_IMAGE}"
  echo "[hana-express] Retagging as ${LOCAL_TAG}"
  podman tag "${HXE_IMAGE}" "${LOCAL_TAG}"
  podman images | awk 'NR==1 || $1 ~ /hana-express/ || $1 ~ /saplabs\/hanaexpress/'
  echo "[hana-express] To push later: podman tag ${LOCAL_TAG} <ACR_NAME>.azurecr.io/demo/${LOCAL_TAG}"
  exit 0
fi

echo "Usage: MODE=standin|express-pull build_hana_db_image.sh"
exit 1

