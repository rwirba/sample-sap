#!/usr/bin/env bash
set -euo pipefail

SERVERS=("sc1" "sc2")
SAP_USER="sapuser"
CONTAINER_DIRS=("j20" "d20" "c20")

for SERVER in "${SERVERS[@]}"; do
  echo "===== Stopping containers on $SERVER ====="
  ssh ${SAP_USER}@${SERVER} '
    cd ~/containers
    echo "Stopping J20..."
    cd j20 && (./runASAP-j20 down || podman-compose down) && sleep 2
    echo "Stopping D20..."
    cd ../d20 && podman-compose down && sleep 2
    echo "Stopping C20..."
    cd ../c20 && podman-compose down
  '
done
