#!/usr/bin/env bash
set -euo pipefail

ACR_NAME="aksdemoacr3"
ACR_SERVER="${ACR_NAME}.azurecr.io"
USERNAME="00000000-0000-0000-0000-000000000000"

echo "[login] Logging into Azure..."
az login --use-device-code

echo "[login] Getting ACR access token..."
TOKEN=$(az acr login --name "$ACR_NAME" --expose-token --query accessToken -o tsv)

echo "[login] Logging into ACR with podman..."
podman login "$ACR_SERVER" --username "$USERNAME" --password "$TOKEN"

echo "[login] ✅ podman is now authenticated to push to $ACR_SERVER"