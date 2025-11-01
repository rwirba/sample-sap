#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express Startup Script (Base Edition)
# Persistent volume reuse + health monitoring
# Author: Ryan DevLab
# -------------------------------------------------------------------

HXE_CONTAINER_NAME="sap-hxe"
HXE_IMAGE_NAME="ryandevlab/sap-hxe:1.0.0"
HXE_DATA_DIR="/data/hxe"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_HOSTNAME="hxehost"
HXE_PASSWORD="HXEHana1"
HXE_UID=12000
HXE_GID=79

# -------------------------------------------------------------------
# 1️⃣ Validate persistence directories
# -------------------------------------------------------------------
if [[ ! -d "${HXE_DATA_DIR}" ]]; then
  echo "[ERROR] Persistent data directory ${HXE_DATA_DIR} not found!"
  echo "Run ./build-and-push.sh first to prepare the host structure."
  exit 1
fi

echo "[INFO] Checking persistent directories..."
for dir in trace/hxehost log config; do
  if [[ ! -d "${HXE_DATA_DIR}/${dir}" ]]; then
    echo "  - Creating missing directory ${HXE_DATA_DIR}/${dir}"
    sudo mkdir -p "${HXE_DATA_DIR}/${dir}"
  fi
done

sudo chown -R ${HXE_UID}:${HXE_GID} "${HXE_DATA_DIR}"
sudo chmod -R 777 "${HXE_DATA_DIR}"

if [[ ! -f "${HXE_PASSWORD_FILE}" ]]; then
  echo "[ERROR] Missing password.json file under ${HXE_DATA_DIR}"
  exit 1
fi

# -------------------------------------------------------------------
# 2️⃣ Pull image if missing locally
# -------------------------------------------------------------------
if ! podman image exists "${HXE_IMAGE_NAME}"; then
  echo "[INFO] Image ${HXE_IMAGE_NAME} not found locally — pulling from Docker Hub..."
  podman pull "${HXE_IMAGE_NAME}"
fi

# -------------------------------------------------------------------
# 3️⃣ Remove any existing container
# -------------------------------------------------------------------
if podman ps -a --format '{{.Names}}' | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing old container ${HXE_CONTAINER_NAME}..."
  podman rm -f "${HXE_CONTAINER_NAME}"
fi

# -------------------------------------------------------------------
# 4️⃣ Start container with persistent host volume
# -------------------------------------------------------------------
echo "[INFO] Starting SAP HANA Express container with persistence..."
CONTAINER_ID=$(podman run -d \
  --name "${HXE_CONTAINER_NAME}" \
  -h "${HXE_HOSTNAME}" \
  --security-opt label=disable \
  -v "${HXE_DATA_DIR}:/hana/mounts" \
  --sysctl kernel.shmmax=1073741824 \
  --sysctl net.ipv4.ip_local_port_range='60000 65535' \
  --ulimit nofile=1048576:1048576 \
  --security-opt systempaths=unconfined \
  -p 39013:39013 \
  -p 39015:39015 \
  -p 39017:39017 \
  "${HXE_IMAGE_NAME}" \
  --agree-to-sap-license \
  --passwords-url file:///hana/mounts/password.json \
  --dont-check-system \
  --dont-check-mount-points)

echo "[INFO] Container started: ${CONTAINER_ID}"

# -------------------------------------------------------------------
# 5️⃣ Wait for HANA to initialize and become healthy
# -------------------------------------------------------------------
echo "[INFO] Waiting up to 5 minutes for HANA to initialize..."
for i in {1..20}; do
  STATUS=$(podman inspect -f '{{.State.Healthcheck.Status}}' "${HXE_CONTAINER_NAME}" 2>/dev/null || echo "starting")
  echo "[INFO] Status check #${i}: ${STATUS}"
  if [[ "${STATUS}" == "healthy" ]]; then
    echo "[✅ SUCCESS] SAP HANA is healthy and running!"
    break
  fi
  sleep 15
done

if [[ "${STATUS}" != "healthy" ]]; then
  echo "[⚠️ WARNING] Container did not reach 'healthy' state after 5 minutes."
  echo "[INFO] Showing last 30 log lines for debugging:"
  podman logs "${HXE_CONTAINER_NAME}" | tail -n 30
fi

# -------------------------------------------------------------------
# 6️⃣ Display connection information
# -------------------------------------------------------------------
EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}')

echo
echo "-------------------------------------------------------------"
echo "[✅ DONE] SAP HANA Express (Base Edition) is running!"
echo "Database Port: ${EC2_IP}:39017"
echo "SYSTEMDB User: SYSTEM / ${HXE_PASSWORD}"
echo "Persistent Volume: ${HXE_DATA_DIR}"
echo "Container Name: ${HXE_CONTAINER_NAME}"
echo "Image Source: ${HXE_IMAGE_NAME}"
echo "-------------------------------------------------------------"
