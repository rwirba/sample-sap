#!/bin/bash
set -euo pipefail

HOST="hello.mitechnology.org"

if [[ ! -f /etc/minikube/env-info.json ]]; then
  echo "❌ Run global-setup.sh first."
  exit 1
fi

CLUSTER_IP=$(jq -r .cluster_ip /etc/minikube/env-info.json)

sudo mkdir -p /etc/cloudflared
CFG="/etc/cloudflared/config.yml"
[[ -f "$CFG" ]] || { echo "❌ $CFG missing. Run your base cloudflared setup."; exit 1; }

if ! grep -q "hostname: ${HOST}" "$CFG"; then
  echo "➕ Adding ${HOST} to Cloudflare ingress..."
  sudo sed -i "/^ingress:/a\  - hostname: ${HOST}\n    service: http://${CLUSTER_IP}" "$CFG"
  sudo systemctl restart cloudflared
else
  echo "✅ ${HOST} already present in ${CFG}"
fi
