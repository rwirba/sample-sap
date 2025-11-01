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
HXE_DATA_DIR="/data/hxe"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_HOSTNAME="hxehost"
PASSWORD_VALUE="HXEHana1"
DOCKERFILE_PATH="$(pwd)/Dockerfile"

# ---- CHECK: Dockerfile exists ----
if [[ ! -f "$DOCKERFILE_PATH" ]]; then
  echo "[ERROR] Dockerfile not found at $DOCKERFILE_PATH"
  exit 1
fi

# ---- APPLY HOST SYSCTL SETTINGS ----
echo "[INFO] Applying SAP-recommended sysctl parameters..."
cat <<EOF >/etc/sysctl.d/99-sap-hana.conf
fs.file-max=20000000
fs.aio-max-nr=262144
vm.memory_failure_early_kill=1
vm.max_map_count=135217728
net.ipv4.ip_local_port_range=40000 60999
EOF
sysctl --system

# ---- PREPARE DATA DIRECTORY ----
echo "[INFO] Ensuring correct ownership and permissions for ${HXE_DATA_DIR}..."
mkdir -p "${HXE_DATA_DIR}/trace" "${HXE_DATA_DIR}/log" "${HXE_DATA_DIR}/config"
sudo chmod 1777 /data/hxe/trace
sudo chown 12000:79 /data/hxe/trace
sudo ls -ld /data/hxe/trace

ls -ld "${HXE_DATA_DIR}" "${HXE_DATA_DIR}/trace"

# ---- PREPARE PASSWORD FILE ----
echo "[INFO] Preparing password JSON..."
cat <<EOF > "${HXE_PASSWORD_FILE}"
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF
chmod 600 "${HXE_PASSWORD_FILE}"
chown 12000:79 "${HXE_PASSWORD_FILE}"

# ---- BUILD WRAPPER IMAGE ----
echo "[INFO] Building SAP HANA Express wrapper image..."
podman build -t "${HXE_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" --format docker .
echo "[INFO] Image build complete:"
podman images | grep saphana || true

# ---- CLEAN UP OLD CONTAINER ----
if podman ps -a --format "{{.Names}}" | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing existing container ${HXE_CONTAINER_NAME}..."
  podman rm -f "${HXE_CONTAINER_NAME}"
fi

# ---- VERIFY FINAL PERMISSIONS ----
echo "[INFO] Final permissions before run:"
ls -ld "${HXE_DATA_DIR}" "${HXE_DATA_DIR}/trace"

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

echo
echo "-------------------------------------------------------------"
echo "[INFO] SAP HANA container starting — showing live logs..."
echo "-------------------------------------------------------------"
echo

# ---- STREAM LOGS LIVE IN BACKGROUND ----
podman logs -f "${HXE_CONTAINER_NAME}" &
LOG_PID=$!

# ---- CHECK HEALTH PERIODICALLY ----
ATTEMPTS=0
MAX_ATTEMPTS=60
STATUS="starting"

while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
  STATUS=$(podman inspect -f '{{.State.Healthcheck.Status}}' "${HXE_CONTAINER_NAME}" 2>/dev/null || echo "starting")
  if [[ "$STATUS" == "healthy" ]]; then
    echo "[✅ SUCCESS] SAP HANA container is healthy and running!"
    break
  fi
  echo "[INFO] Status check #$((ATTEMPTS+1)) → ${STATUS}"
  sleep 15
  ((ATTEMPTS++))
done

# ---- STOP LOG STREAM IF STILL RUNNING ----
if ps -p ${LOG_PID} >/dev/null 2>&1; then
  kill ${LOG_PID} >/dev/null 2>&1 || true
fi

if [[ "$STATUS" != "healthy" ]]; then
  echo "[⚠️ WARNING] Container not marked healthy after ${MAX_ATTEMPTS} attempts."
fi

# ---- DISPLAY CONNECTION INFO ----
EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<EC2_PUBLIC_IP>")
echo
echo "-------------------------------------------------------------"
echo "[✅ DONE] SAP HANA Express startup complete."
echo "Web Cockpit:   http://${EC2_IP}:51000"
echo "Database Port: ${EC2_IP}:39017"
echo "-------------------------------------------------------------"
