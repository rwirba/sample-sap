#!/usr/bin/env bash
set -euo pipefail

: "${ACR_NAME:?Set ACR_NAME (e.g., myregistry)}"
LOGIN_SERVER="${ACR_NAME}.azurecr.io"

echo "[acr-login] Getting access token for $LOGIN_SERVER ..."
TOKEN="$(az acr login -n "$ACR_NAME" --expose-token --output tsv --query accessToken)"

podman login "$LOGIN_SERVER" -u 00000000-0000-0000-0000-000000000000 -p "$TOKEN"
echo "[acr-login] Podman is logged into $LOGIN_SERVER"