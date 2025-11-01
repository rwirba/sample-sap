#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express Image Build + Persistent Volume Setup + Push
# Host-mounted persistence (idempotent)
# Author: Ryan DevLab
# -------------------------------------------------------------------

HXE_IMAGE_NAME="ryandevlab/sap-hxe:1.0.0"
DOCKERFILE_PATH="$(pwd)/Dockerfile"
HXE_DATA_DIR="/data/hxe"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_UID=12000
HXE_GID=79
HXE_PASSWORD="HXEHana1"

# -------------------------------------------------------------------
# Verify base path and mount volume if needed
# -------------------------------------------------------------------
if [[ ! -d "/data" ]]; then
  echo "[INFO] Creating /data base directory..."
  sudo mkdir -p /data
fi

# Optional: auto-mount EBS device (uncomment and adjust as needed)
# DEVICE="/dev/xvdf"
# if lsblk | grep -q "$(basename ${DEVICE})"; then
#   echo "[INFO] Checking EBS volume mount..."
#   grep -q "/data" /etc/fstab || echo "${DEVICE}  /data  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab
#   sudo mount -a
# fi

# -------------------------------------------------------------------
# Create persistent directory tree (idempotent)
# -------------------------------------------------------------------
echo "[INFO] Ensuring persistent directories exist under ${HXE_DATA_DIR}..."
for dir in trace/hxehost log config; do
  if [[ ! -d "${HXE_DATA_DIR}/${dir}" ]]; then
    echo "  - Creating ${HXE_DATA_DIR}/${dir}"
    sudo mkdir -p "${HXE_DATA_DIR}/${dir}"
  fi
done

# -------------------------------------------------------------------
# Apply consistent ownership & permissions
# -------------------------------------------------------------------
echo "[INFO] Applying SAP ownership and permissions..."
sudo chown -R ${HXE_UID}:${HXE_GID} "${HXE_DATA_DIR}"
sudo chmod -R 777 "${HXE_DATA_DIR}"
sudo ls -ld "${HXE_DATA_DIR}" "${HXE_DATA_DIR}/trace" "${HXE_DATA_DIR}/log"

# -------------------------------------------------------------------
# Prepare password file (only if missing)
# -------------------------------------------------------------------
if [[ ! -f "${HXE_PASSWORD_FILE}" ]]; then
  echo "[INFO] Creating password file..."
  cat <<EOF | sudo tee "${HXE_PASSWORD_FILE}" >/dev/null
{
  "master_password": "${HXE_PASSWORD}"
}
EOF
  sudo chmod 600 "${HXE_PASSWORD_FILE}"
  sudo chown ${HXE_UID}:${HXE_GID} "${HXE_PASSWORD_FILE}"
else
  echo "[INFO] Password file already exists — skipping."
fi

# -------------------------------------------------------------------
# Apply system tunables (safe to re-run)
# -------------------------------------------------------------------
echo "[INFO] Applying SAP-recommended sysctl settings..."
sudo tee /etc/sysctl.d/99-sap-hana.conf >/dev/null <<EOF
fs.file-max=20000000
fs.aio-max-nr=262144
vm.memory_failure_early_kill=1
vm.max_map_count=135217728
net.ipv4.ip_local_port_range=40000 60999
EOF
sudo sysctl --system >/dev/null

# -------------------------------------------------------------------
# Build image
# -------------------------------------------------------------------
echo "[INFO] Building SAP HANA Express wrapper image..."
podman build -t "${HXE_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" --format docker

echo "[INFO] Build complete. Local image summary:"
podman images | grep sap-hxe || true

# -------------------------------------------------------------------
# Authenticate & Push to Docker Hub
# -------------------------------------------------------------------
read -p "Enter your Docker Hub username: " DOCKER_USER
echo -n "Enter your Docker Hub password: "
read -s DOCKER_PASS
echo
echo "${DOCKER_PASS}" | podman login -u "${DOCKER_USER}" --password-stdin docker.io

echo "[INFO] Pushing image to Docker Hub..."
podman push "${HXE_IMAGE_NAME}"

echo
echo "-------------------------------------------------------------"
echo "[SUCCESS] Image built, pushed, and host persistence ready!"

