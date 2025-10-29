#!/bin/bash
set -euo pipefail

# ========= CONFIG =========
S3_BUCKET="ryandevlab-bucket"
S3_TUNNEL_PATH="s3://${S3_BUCKET}/cloudflare-tunnels"
LOCAL_CF_DIR="/home/ec2-user/.cloudflared"
MINIKUBE_INFO="/etc/minikube/env-info.json"

echo "🚀 Syncing local Cloudflare tunnels to S3..."
echo "📂 Source: $LOCAL_CF_DIR"
echo "📦 Destination: $S3_TUNNEL_PATH"

# --- Ensure AWS CLI is available ---
if ! command -v aws &>/dev/null; then
  echo "⚠️ AWS CLI not found. Installing..."
  sudo dnf install -y awscli || sudo yum install -y awscli
fi

# --- Ensure jq is available ---
if ! command -v jq &>/dev/null; then
  echo "⚙️ Installing jq..."
  sudo dnf install -y jq || sudo yum install -y jq
fi

# --- Validate directory ---
if [[ ! -d "$LOCAL_CF_DIR" ]]; then
  echo "❌ Cloudflare directory not found: $LOCAL_CF_DIR"
  exit 1
fi

# --- Create base path in S3 if needed ---
aws s3 ls "$S3_TUNNEL_PATH" >/dev/null 2>&1 || aws s3 mb "$S3_TUNNEL_PATH"

# --- Loop through JSON credentials in ~/.cloudflared ---
FOUND_ANY=false
for JSON_FILE in "$LOCAL_CF_DIR"/*.json; do
  [[ -f "$JSON_FILE" ]] || continue
  FOUND_ANY=true

  TUNNEL_ID=$(jq -r '.TunnelID' "$JSON_FILE" 2>/dev/null || echo "")
  if [[ -z "$TUNNEL_ID" || "$TUNNEL_ID" == "null" ]]; then
    echo "⚠️ Skipping $JSON_FILE (not a tunnel credentials file)"
    continue
  fi

  BASENAME=$(basename "$JSON_FILE" .json)
  APP_NAME=""
  case "$BASENAME" in
    *dashboard*) APP_NAME="dashboard" ;;
    *hello*) APP_NAME="hello" ;;
    *ads*) APP_NAME="ads" ;;
    *) APP_NAME="$BASENAME" ;;
  esac

  DEST_FILE="${APP_NAME}-tunnel.json"
  echo "⬆️ Uploading ${JSON_FILE} → ${S3_TUNNEL_PATH}/${DEST_FILE}"
  aws s3 cp "$JSON_FILE" "${S3_TUNNEL_PATH}/${DEST_FILE}" --quiet

  # Save a local copy under /etc/minikube
  sudo mkdir -p /etc/minikube
  sudo cp "$JSON_FILE" "/etc/minikube/${DEST_FILE}"
done

if [[ "$FOUND_ANY" == false ]]; then
  echo "⚠️ No .json tunnel credentials found under $LOCAL_CF_DIR"
  exit 0
fi

# --- Update env-info.json if it exists ---
if [[ -f "$MINIKUBE_INFO" ]]; then
  echo "🔄 Updating /etc/minikube/env-info.json with new tunnel references..."
  jq '.tunnels.dashboard = "/etc/minikube/dashboard-tunnel.json" |
      .tunnels.hello = "/etc/minikube/hello-tunnel.json" |
      .tunnels.ads = "/etc/minikube/ads-tunnel.json"' \
      "$MINIKUBE_INFO" | sudo tee "$MINIKUBE_INFO" >/dev/null
else
  echo "⚠️ env-info.json not found. You may need to run global-setup.sh first."
fi

echo "✅ All tunnels synced to S3 successfully."
aws s3 ls "$S3_TUNNEL_PATH" | awk '{print "   " $NF}'
