#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express setup on RHEL9 using Podman (runc runtime)
# Author: Ryan DevLab
# -------------------------------------------------------------------

# ---- CONFIGURATION ----
HXE_CONTAINER_NAME="hxexsa1"
HXE_IMAGE_NAME="ryandevlab/saphana:1.0.0"
HXE_DATA_DIR="$(pwd)/data"
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
sudo tee /etc/sysctl.d/99-sap-hana.conf >/dev/null <<EOF
fs.file-max=20000000
fs.aio-max-nr=262144
vm.memory_failure_early_kill=1
vm.max_map_count=135217728
net.ipv4.ip_local_port_range=40000 60999
EOF
sudo sysctl --system

# ---- PREPARE PASSWORD FILE ----
echo "[INFO] Preparing data directory and password JSON..."
sudo mkdir -p "${HXE_DATA_DIR}"
cat <<EOF | sudo tee "${HXE_PASSWORD_FILE}" >/dev/null
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF
sudo chmod 600 "${HXE_PASSWORD_FILE}"
sudo chown 12000:79 "${HXE_PASSWORD_FILE}"

# ---- BUILD WRAPPER IMAGE ----
echo "[INFO] Building custom HANA Express image using Dockerfile: ${DOCKERFILE_PATH}"
sudo podman build -t "${HXE_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" --format docker .

echo "[INFO] Image build complete:"
sudo podman images | grep saphana || true

# ---- CLEAN UP OLD CONTAINER ----
if sudo podman ps -a --format "{{.Names}}" | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing existing container ${HXE_CONTAINER_NAME}..."
  sudo podman rm -f "${HXE_CONTAINER_NAME}"
fi

# ---- RUN NEW CONTAINER ----
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
  -p 39013:39013 -p 39015:39015 -p 39017:39017 \
  -p 51000-51060:51000-51060 -p 53075:53075 \
  "${HXE_IMAGE_NAME}" \
  --agree-to-sap-license \
  --passwords-url file:///hana/mounts/password.json \
  --no-proxy localhost,127.0.0.1,"${HXE_HOSTNAME}"

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
