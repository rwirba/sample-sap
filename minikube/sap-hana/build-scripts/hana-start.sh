#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express Container Startup Script
# Persistent volume + post-install automation
# Author: Ryan DevLab
# -------------------------------------------------------------------

HXE_CONTAINER_NAME="hxexsa1"
HXE_IMAGE_NAME="ryandevlab/saphana:1.0.0"
HXE_DATA_DIR="/data/hxe"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_HOSTNAME="hxehost"
PASSWORD_VALUE="HXEHana1"

# -------------------------------------------------------------------
# 1. Persistent directory setup (idempotent)
# -------------------------------------------------------------------
echo "[INFO] Creating persistent structure..."
sudo mkdir -p "${HXE_DATA_DIR}/trace/hxehost" "${HXE_DATA_DIR}/log" "${HXE_DATA_DIR}/config"

# Set ownership and permissions — tolerant of existing data
sudo chown -R 12000:79 "${HXE_DATA_DIR}" || true
sudo chmod -R 777 "${HXE_DATA_DIR}" || true

# -------------------------------------------------------------------
# 2. Password JSON (only if missing)
# -------------------------------------------------------------------
if [[ ! -f "${HXE_PASSWORD_FILE}" ]]; then
  echo "[INFO] Creating password file..."
  cat <<EOF | sudo tee "${HXE_PASSWORD_FILE}" >/dev/null
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF
  sudo chmod 600 "${HXE_PASSWORD_FILE}"
  sudo chown 12000:79 "${HXE_PASSWORD_FILE}"
fi

# -------------------------------------------------------------------
# 3. Apply high open file descriptor limits (root only)
# -------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  echo "[INFO] Ensuring high open-file limits for sapuser..."
  if ! grep -q "sapuser" /etc/security/limits.conf; then
    sudo tee -a /etc/security/limits.conf >/dev/null <<'EOF'
sapuser soft nofile 1048576
sapuser hard nofile 1048576
EOF
  fi

  # Enable pam_limits where applicable
  sudo sed -i '/pam_limits.so/s/^#//g' /etc/pam.d/common-session* || true
else
  echo "[WARN] Running as non-root — unable to raise PAM limits globally."
fi

# -------------------------------------------------------------------
# 4. Cleanup any existing container
# -------------------------------------------------------------------
if podman ps -a --format '{{.Names}}' | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing existing container ${HXE_CONTAINER_NAME}..."
  podman rm -f "${HXE_CONTAINER_NAME}"
fi

# -------------------------------------------------------------------
# 5. Start HANA container
# -------------------------------------------------------------------
echo "[INFO] Starting SAP HANA Express container with persistent volume..."
podman run -d \
  --name "${HXE_CONTAINER_NAME}" \
  -h "${HXE_HOSTNAME}" \
  --restart=always \
  --security-opt label=disable \
  --security-opt systempaths=unconfined \
  -v "${HXE_DATA_DIR}:/hana/mounts" \
  --sysctl kernel.shmmax=1073741824 \
  --sysctl net.ipv4.ip_local_port_range='60000 65535' \
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

# -------------------------------------------------------------------
# 6. Wait and monitor logs
# -------------------------------------------------------------------
echo "[INFO] Waiting for HANA to initialize (2 minutes)..."
sleep 120

echo "[INFO] Checking container health..."
STATUS=$(podman inspect -f '{{.State.Healthcheck.Status}}' "${HXE_CONTAINER_NAME}" 2>/dev/null || echo "unknown")
echo "[INFO] Health: ${STATUS}"

# -------------------------------------------------------------------
# 7. Optional: Post-install for Cockpit & XS
# -------------------------------------------------------------------
echo "[INFO] Checking for XS Advanced / Cockpit installation..."
if ! sudo podman exec -it --user hxeadm "${HXE_CONTAINER_NAME}" bash -c "cd /hana/shared/HXE/hdblcm && ./hdblcm --list_components | grep -q 'xs'" >/dev/null 2>&1; then
  echo "[INFO] Installing XS Advanced and Cockpit..."
  sudo podman exec -it --user hxeadm "${HXE_CONTAINER_NAME}" bash -c "
    cd /hana/shared/HXE/hdblcm && \
    ./hdblcm --action=add_components --components=xs --batch && \
    /usr/sap/HXE/HDB90/HDB restart"
else
  echo "[INFO] XS Advanced already installed — skipping."
fi

# -------------------------------------------------------------------
# 8. Verify HANA & Cockpit are reachable
# -------------------------------------------------------------------
echo "[INFO] Checking cockpit ports..."
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
