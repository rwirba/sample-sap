#!/usr/bin/env bash
set -euo pipefail

SERVERS=("sc1" "sc2")
SAP_USER="sapuser"

for SERVER in "${SERVERS[@]}"; do
  echo "===== Starting containers on $SERVER ====="
  ssh ${SAP_USER}@${SERVER} '
    cd ~/containers
    echo "Starting C20..."
    cd c20 && podman-compose up -d && sleep 10
    echo "Starting D20..."
    cd ../d20 && podman-compose up -d && sleep 10
    echo "Starting J20..."
    cd ../j20 && (./runASAP-j20 up || podman-compose up -d)
  '
done
