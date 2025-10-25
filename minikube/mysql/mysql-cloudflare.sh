#!/bin/bash
set -euo pipefail

HOST="mysql.mitechnology.org"

if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Run global-setup.sh first."
  exit 1
fi

CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)

# Fetch NodePort used by MySQL Service
NODE_PORT=$(kubectl get svc mysql-db -n demo -o jsonpath='{.spec.ports[0].nodePort}')
if [[ -z "$NODE_PORT" ]]; then
  echo "❌ Could not determine MySQL NodePort. Deploy MySQL first."
  exit 1
fi

sudo mkdir -p /etc/cloudflared
CFG="/etc/cloudflared/config.yml"
[[ -f "$CFG" ]] || { echo "❌ $CFG missing. Run your base cloudflared setup."; exit 1; }

# Add TCP rule if missing
if ! grep -q "hostname: ${HOST}" "$CFG"; then
  echo "➕ Adding ${HOST} (TCP) to Cloudflare ingress..."
  sudo sed -i "/^ingress:/a\  - hostname: ${HOST}\n    service: tcp://${CLUSTER_IP}:${NODE_PORT}" "$CFG"
  sudo systemctl restart cloudflared
else
  echo "✅ ${HOST} already present in ${CFG}"
fi

echo "🔑 Connect from MySQL Workbench using:"
echo "  Hostname: ${HOST}"
echo "  Port: 3306 (Cloudflare maps to NodePort ${NODE_PORT})"
echo "  User: appuser | Password: apppass | DB: appdb (per values.yaml)"
