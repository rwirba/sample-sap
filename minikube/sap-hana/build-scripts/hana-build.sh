#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express setup on RHEL9 using Podman (runc runtime)
# Author: Ryan DevLab
# -------------------------------------------------------------------
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

# ---- VALIDATION ----
if [[ ! -f "$DOCKERFILE_PATH" ]]; then
  echo "[❌ ERROR] Dockerfile not found at: $DOCKERFILE_PATH"
  exit 1
fi

# ---- APPLY HOST SYSCTL SETTINGS ----
echo "[INFO] Applying SAP-recommended sysctl parameters..."
cat <<EOF | tee /etc/sysctl.d/99-sap-hana.conf >/dev/null
fs.file-max=20000000
fs.aio-max-nr=262144
vm.memory_failure_early_kill=1
vm.max_map_count=135217728
net.ipv4.ip_local_port_range=40000 60999
EOF
sysctl --system >/dev/null 2>&1 || true

# ---- PREPARE PASSWORD FILE ----
echo "[INFO] Preparing password JSON..."
mkdir -p "${HXE_DATA_DIR}"
cat <<EOF > "${HXE_PASSWORD_FILE}"
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF
chmod 600 "${HXE_PASSWORD_FILE}"

# ---- FIX HANA DIRECTORY OWNERSHIP (critical for /hana/mounts access) ----
echo "[INFO] Setting ownership for SAP HANA data directory..."
sudo mkdir -p /data/hxe
chown -R 12000:79 "${HXE_DATA_DIR}"
chmod -R 775 "${HXE_DATA_DIR}"

# ---- BUILD WRAPPER IMAGE ----
echo "[INFO] Building SAP HANA Express image using ${DOCKERFILE_PATH} ..."
podman build -t "${HXE_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" --format docker

echo "[INFO] Image build complete:"
podman images | grep saphana || true

# ---- REMOVE OLD CONTAINER IF EXISTS ----
if podman ps -a --format "{{.Names}}" | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing existing container ${HXE_CONTAINER_NAME}..."
  podman rm -f "${HXE_CONTAINER_NAME}" || true
fi

# ---- RUN NEW CONTAINER ----
echo "[INFO] Starting SAP HANA Express container..."
podman run -d \
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

echo "[INFO] Waiting for SAP HANA to initialize (this may take 1–2 minutes)..."
sleep 60

# ---- VALIDATE STATUS ----
if podman ps --filter "name=${HXE_CONTAINER_NAME}" --filter "status=running" --format "{{.Names}}" | grep -q "${HXE_CONTAINER_NAME}"; then
  echo "[✅ SUCCESS] SAP HANA Express is now running!"
else
  echo "[⚠️ WARNING] Container is not running. Checking logs..."
  podman logs "${HXE_CONTAINER_NAME}" | tail -n 50
  echo "[❌ ERROR] SAP HANA failed to start. Please review logs above."
  exit 1
fi

# ---- DISPLAY ACCESS INFO ----
EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<EC2_PUBLIC_IP>")
echo
echo "-------------------------------------------------------------"
echo "SAP HANA Express successfully started!"
echo "Web Cockpit:   http://${EC2_IP}:51000"
echo "Database Port: ${EC2_IP}:39017"
echo "-------------------------------------------------------------"
