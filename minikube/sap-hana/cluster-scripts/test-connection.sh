#!/usr/bin/env bash
set -euo pipefail

NODE_IP=$(minikube ip)
PORT=39017
PASS="HXEHana1"

echo "[INFO] Testing SAP HANA SYSTEMDB connection..."
sudo podman run --rm --network host ryandevlab/sap-hana:1.0.0 \
  /usr/sap/HXE/HDB90/exe/hdbsql -n "${NODE_IP}:${PORT}" -d SYSTEMDB -u SYSTEM -p "${PASS}" \
  "SELECT DATABASE_NAME, ACTIVE_STATUS FROM SYS.M_DATABASES;"
