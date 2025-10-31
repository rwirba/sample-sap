#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# SAP HANA Express (Full Edition) Setup Script for RHEL9 + Podman
# Author: Ryan DevLab
# -------------------------------------------------------------------

# Ensure we’re running as root for sysctl + podman operations
if [[ $EUID -ne 0 ]]; then
  echo "[INFO] Re-running with sudo privileges..."
  exec sudo bash "$0" "$@"
fi

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
HXE_CONTAINER_NAME="hxexsa1"
HXE_IMAGE_NAME="ryandevlab/saphana:1.0.0"
HXE_BASE_IMAGE="docker.io/saplabs/hanaexpress:2.00.061.00.20220519.1"
HXE_DATA_DIR="/data/hxe"
HXE_PASSWORD_FILE="${HXE_DATA_DIR}/password.json"
HXE_HOSTNAME="hxehost"
PASSWORD_VALUE="HXEHana1"
DOCKERFILE_PATH="$(pwd)/Dockerfile"

# -------------------------------------------------------------------
# 1️⃣ Ensure base system prereqs and runtime are ready
# -------------------------------------------------------------------
echo "[INFO] Installing system dependencies..."
dnf -y install podman podman-docker buildah skopeo runc git python3-pip || true

echo "[INFO] Verifying runtime configuration..."
mkdir -p /etc/containers
cat <<EOC > /etc/containers/containers.conf
[engine]
runtime = "runc"
default_runtime = "runc"
EOC
podman system migrate || true

# -------------------------------------------------------------------
# 2️⃣ System tuning (HANA requires specific kernel params)
# -------------------------------------------------------------------
echo "[INFO] Applying SAP-recommended sysctl parameters..."
tee /etc/sysctl.d/99-sap-hana.conf >/dev/null <<EOF
fs.file-max=20000000
fs.aio-max-nr=262144
vm.memory_failure_early_kill=1
vm.max_map_count=135217728
net.ipv4.ip_local_port_range=40000 60999
EOF
sysctl --system

# -------------------------------------------------------------------
# 3️⃣ Prepare data directory and password JSON
# -------------------------------------------------------------------
echo "[INFO] Preparing data directory and password file..."
mkdir -p "${HXE_DATA_DIR}"
cat <<EOF > "${HXE_PASSWORD_FILE}"
{
  "master_password": "${PASSWORD_VALUE}"
}
EOF

# Ownership must match SAP’s runtime user inside container
chown -R 12000:79 /data
chmod -R 775 /data

# -------------------------------------------------------------------
# 4️⃣ Build custom wrapper image (full edition base)
# -------------------------------------------------------------------
echo "[INFO] Building wrapper image from: ${DOCKERFILE_PATH}"
if [[ ! -f "$DOCKERFILE_PATH" ]]; then
  echo "[ERROR] Dockerfile not found at $DOCKERFILE_PATH"
  exit 1
fi

podman build -t "${HXE_IMAGE_NAME}" --build-arg HXE_BASE_IMAGE="${HXE_BASE_IMAGE}" -f "${DOCKERFILE_PATH}" --format docker .

echo "[INFO] Image build complete:"
podman images | grep saphana || true

# -------------------------------------------------------------------
# 5️⃣ Remove existing container (if any)
# -------------------------------------------------------------------
if podman ps -a --format "{{.Names}}" | grep -q "^${HXE_CONTAINER_NAME}$"; then
  echo "[INFO] Removing old container..."
  podman rm -f "${HXE_CONTAINER_NAME}"
fi

# -------------------------------------------------------------------
# 6️⃣ Run SAP HANA Express container
# -------------------------------------------------------------------
echo "[INFO] Starting SAP HANA Express (Full Edition) container..."
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

# -------------------------------------------------------------------
# 7️⃣ Monitor and print connection info
# -------------------------------------------------------------------
echo "[INFO] Waiting for container to initialize (1–2 min)..."
sleep 90

podman ps

EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}')
echo
echo "----------------------------------------------------------"
echo "✅ SAP HANA Express successfully started!"
echo "Web Cockpit:   http://${EC2_IP}:51000"
echo "Database Port: ${EC2_IP}:39017"
echo "----------------------------------------------------------"
