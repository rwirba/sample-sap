#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express setup and wrapper build
# Author: Ryan DevLab
# -------------------------------------------------------------------

# ---- REQUIRE SUDO ----
if [[ $EUID -ne 0 ]]; then
  echo "[INFO] Re-running with sudo privileges..."
  exec sudo bash "$0" "$@"
fi

# ---- CONFIGURATION ----
HXE_CONTAINER_NAME="hxexsa1"
HXE_IMAGE_NAME="ryandevlab/saphana:1.0.0"
HXE_DATA_DIR="$(pwd)/data"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_HOSTNAME="hxehost"
PASSWORD_VALUE="HXEHana1"
DOCKERFILE_PATH="$(pwd)/Dockerfile"

# ---- VALIDATE DOCKERFILE ----
if [[ ! -f "$DOCKERFILE_PATH" ]]; then
  echo "[ERROR] Dockerfile not found at $DOCKERFILE_PATH"
  exit 1
fi

# ---- BUILD IMAGE ----
echo "[INFO] Building wrapper image from: ${DOCKERFILE_PATH}"
sudo podman build \
  -t "${HXE_IMAGE_NAME}" \
  -f "${DOCKERFILE_PATH}" \
  --format docker

# ---- VERIFY IMAGE ----
echo "[INFO] Image build complete:"
sudo podman images | grep saphana || true

# ---- CLEANUP OLD CONTAINER ----
if sudo podman ps -a --format "{{.Names}}" | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing old container ${HXE_CONTAINER_NAME}..."
  sudo podman rm -f "${HXE_CONTAINER_NAME}"
fi

# ---- PREPARE DATA ----
echo "[INFO] Preparing HANA data directory..."
sudo mkdir -p "${HXE_DATA_DIR}"
cat <<EOF | sudo tee "${HXE_PASSWORD_FILE}" >/dev/null
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF
sudo chmod 600 "${HXE_PASSWORD_FILE}"
sudo chown 12000:79 "${HXE_PASSWORD_FILE}"

# ---- RUN CONTAINER ----
echo "[INFO] Starting SAP HANA Express container..."
sudo podman run -d \
  --name "${HXE_CONTAINER_NAME}" \
  -h "${HXE_HOSTNAME}" \
  --restart=always \
  -v "${HXE_DATA_DIR}:/hana/mounts" \
  --ulimit nofile=1048576:1048576 \
  --sysctl kernel.shmmax=1073741824 \
  --sysctl net.ipv4.ip_local_port_range='60000 65535' \
  --security-opt systempaths=unconfined \
  -p 39013:39013 \
  -p 39015:39015 \
  -p 39017:39017 \
  -p 51000-51060:51000-51060 \
  -p 53075:53075 \
  "${HXE_IMAGE_NAME}" \
  --agree-to-sap-license \
  --passwords-url file:///hana/mounts/password.json \
  --dont-check-system \
  --dont-check-mount-points

# ---- STATUS ----
echo "[INFO] Waiting for container to initialize..."
sleep 30
sudo podman ps

echo
echo "[✅ SUCCESS] SAP HANA Express is now running!"
EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<EC2_PUBLIC_IP>")
echo "-------------------------------------------------------------"
echo "Web Cockpit:   http://${EC2_IP}:51000"
echo "Database Port: ${EC2_IP}:39017"
echo "-------------------------------------------------------------"
