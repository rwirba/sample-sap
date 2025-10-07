#!/usr/bin/env bash
set -euo pipefail

if ! az account show >/dev/null 2>&1; then
  echo "[aks-login] Launching device-code login..."
  az login --use-device-code >/dev/null
fi

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${AKS_NAME:?Set AKS_NAME}"

az account set -s "$SUBSCRIPTION_ID"
echo "[aks-login] Fetching kubeconfig for $AKS_NAME ..."
az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKS_NAME" --overwrite-existing

echo "[aks-login] Converting kubeconfig for kubelogin (azurecli mode) ..."
kubelogin convert-kubeconfig -l azurecli

kubectl cluster-info
kubectl get nodes -o wide