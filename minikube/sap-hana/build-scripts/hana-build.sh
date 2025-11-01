#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express (Full Edition) setup on RHEL9 using Podman
# Author: Ryan DevLab
# -------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "[INFO] Re-running with sudo privileges..."
  exec sudo bash "$0" "$@"
fi

HXE_CONTAINER_NAME="hxexsa1"
HXE_IMAGE_NAME="ryandevlab/saphana:1.0.0"
HXE_DATA_DIR="/data/hxe"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_HOSTNAME="hxehost"
PASSWORD_VALUE="HXEHana1"
DOCKERFILE_PATH="$(pwd)/Dockerfile"

echo "[INFO] Applying SAP-recommended sysctl parameters..."
cat <<EOF >/etc/sysctl.d/99-sap-hana.conf
fs.file-max=20000000
fs.aio-max-nr=262144
vm.memory_failure_early_kill=1
vm.max_map_count=135217728
net.ipv4.ip_local_port_range=40000 60999
EOF
sysctl --system

echo "[INFO] Creating persistent directories..."
sudo mkdir -p "${HXE_DATA_DIR}/trace/hxehost" "${HXE_DATA_DIR}/log" "${HXE_DATA_DIR}/config"
sudo chmod -R 777 "${HXE_DATA_DIR}"
sudo chown -R 12000:79 "${HXE_DATA_DIR}"
sudo ls -ld "${HXE_DATA_DIR}" "${HXE_DATA_DIR}/trace" "${HXE_DATA_DIR}/trace/hxehost"

echo "[INFO] Preparing password JSON..."
cat <<EOF > "${HXE_PASSWORD_FILE}"
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF
sudo chmod 600 "${HXE_PASSWORD_FILE}"
sudo chown 12000:79 "${HXE_PASSWORD_FILE}"

echo "[INFO] Building SAP HANA Express (Full Edition) image..."
podman build -t "${HXE_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" --format docker
podman images | grep saphana || true

if podman ps -a --format '{{.Names}}' | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing existing container ${HXE_CONTAINER_NAME}..."
  podman rm -f "${HXE_CONTAINER_NAME}"
fi

echo "[INFO] Starting SAP HANA Express (Full Edition) container..."
podman run -d \
  --name "${HXE_CONTAINER_NAME}" \
  -h "${HXE_HOSTNAME}" \
  --restart=always \
  -v "${HXE_DATA_DIR}:/hana/mounts:Z" \
  --ulimit nofile=1048576:1048576 \
  --sysctl kernel.shmmax=1073741824 \
  --sysctl net.ipv4.ip_local_port_range='60000 65535' \
  --security-opt systempaths=unconfined \
  -p 39013:39013 \
  -p 39015:39015 \
  -p 39017:39017 \
  -p 51000:51000 \
  -p 51001:51001 \
  -p 51060:51060 \
  -p 53075:53075 \
  "${HXE_IMAGE_NAME}" \
  --agree-to-sap-license \
  --passwords-url file:///hana/mounts/password.json \
  --dont-check-system \
  --dont-check-mount-points

echo
echo "-------------------------------------------------------------"
echo "[INFO] SAP HANA container starting — live logs below"
echo "-------------------------------------------------------------"
echo

ATTEMPTS=0
MAX_ATTEMPTS=60
while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
  podman logs --since 10s "${HXE_CONTAINER_NAME}" || true
  STATUS=$(podman inspect -f '{{.State.Healthcheck.Status}}' "${HXE_CONTAINER_NAME}" 2>/dev/null || echo "starting")
  echo "[INFO] Status check #$((ATTEMPTS+1)) → ${STATUS}"
  [[ "$STATUS" == "healthy" ]] && break
  sleep 15
  ((ATTEMPTS++))
done

if [[ "$STATUS" == "healthy" ]]; then
  echo "[✅ SUCCESS] SAP HANA container is healthy and running!"
else
  echo "[⚠️ WARNING] Container not marked healthy after ${MAX_ATTEMPTS} attempts."
fi

EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<EC2_PUBLIC_IP>")
echo
echo "-------------------------------------------------------------"
echo "[✅ DONE] SAP HANA Express (Full Edition) startup complete."
echo "Web Cockpit:   https://${EC2_IP}:51001"
echo "HTTP Cockpit:  http://${EC2_IP}:51000"
echo "Database Port: ${EC2_IP}:39017"
echo "-------------------------------------------------------------"
