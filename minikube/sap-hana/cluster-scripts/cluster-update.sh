#!/bin/bash
set -e

IMAGE="ryandevlab/sap-hana:1.0.0"
CHART_PATH="./sap-hana-chart"
NAMESPACE="demo"

echo "🔄 Updating SAP HANA Express image and redeploying..."

# 1️⃣ Build new image
echo "[1/3] Building updated image..."
podman build -t "$IMAGE" -f ./Dockerfile --format docker

# 2️⃣ Push to Docker Hub
echo "[2/3] Logging into Docker Hub..."
podman login docker.io
echo "[3/3] Pushing image to Docker Hub..."
podman push "$IMAGE"

# 3️⃣ Redeploy Helm chart
echo
echo "🚀 Redeploying Helm release..."
helm upgrade --install sap-hana "$CHART_PATH" \
  --namespace "$NAMESPACE" \
  --wait

echo
echo "✅ Update complete — SAP HANA redeployed successfully!"
kubectl get pods -n "$NAMESPACE"
