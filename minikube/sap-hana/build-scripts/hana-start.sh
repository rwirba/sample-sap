#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express Container Startup Script
# Persistent volume + post-install automation
# -------------------------------------------------------------------

HXE_CONTAINER_NAME="hxexsa1"
HXE_IMAGE_NAME="ryandevlab/saphana:1.0.0"
HXE_DATA_DIR="/data/hxe"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_HOSTNAME="hxehost"
PASSWORD_VALUE="HXEHana1"

# Create persistent structure
sudo mkdir -p "${HXE_DATA_DIR}/trace/hxehost" "${HXE_DATA_DIR}/log" "${HXE_DATA_DIR}/config"
sudo chmod -R 777 "${HXE_DATA_DIR}"
sudo chown -R 12000:79 "${HXE_DATA_DIR}"

# Prepare password JSON (only if not already there)
if [[ ! -f "${HXE_PASSWORD_FILE}" ]]; then
  echo "[INFO] Creating password file..."
  cat <<EOF > "${HXE_PASSWORD_FILE}"
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF
  sudo chmod 600 "${HXE_PASSWORD_FILE}"
  sudo chown 12000:79 "${HXE_PASSWORD_FILE}"
fi

# Remove old container if exists
if podman ps -a --format '{{.Names}}' | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing existing container ${HXE_CONTAINER_NAME}..."
  podman rm -f "${HXE_CONTAINER_NAME}"
fi

# Run container
echo "[INFO] Starting SAP HANA container with persistent volume..."
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

echo "[INFO] Waiting for container to initialize..."
sleep 120

# Post-setup: Install XS Advanced + Cockpit if not present
echo "[INFO] Checking if Cockpit is already installed..."
if ! sudo podman exec -it --user hxeadm "${HXE_CONTAINER_NAME}" bash -c "test -d /hana/shared/HXE/hdblcm || exit 1; cd /hana/shared/HXE/hdblcm && ./hdblcm --list_components | grep -q 'xs'" >/dev/null 2>&1; then
  echo "[INFO] Installing XS Advanced and Cockpit..."
  sudo podman exec -it --user hxeadm "${HXE_CONTAINER_NAME}" bash -c "
    cd /hana/shared/HXE/hdblcm && \
    ./hdblcm --action=add_components --components=xs --batch && \
    /usr/sap/HXE/HDB90/HDB restart"
else
  echo "[INFO] Cockpit already installed — skipping XS installation."
fi

# Verify HANA and Cockpit are running
sudo podman exec -it "${HXE_CONTAINER_NAME}" bash -c "ss -tuln | grep 5100 || true"

EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<EC2_PUBLIC_IP>")

echo
echo "-------------------------------------------------------------"
echo "[✅ DONE] SAP HANA Express (Full Edition) startup complete."
echo "Web Cockpit (HTTPS): https://${EC2_IP}:51001"
echo "Web Cockpit (HTTP):  http://${EC2_IP}:51000"
echo "Database Port:       ${EC2_IP}:39017"
echo "Persistent Volume:   ${HXE_DATA_DIR}"
echo "-------------------------------------------------------------"
