#!/bin/bash
set -e

echo "🚀 Deploying SAP HANA Express to Minikube..."

# Namespace for HANA
NAMESPACE="hana"

# Create namespace if missing
kubectl get ns $NAMESPACE &>/dev/null || kubectl create ns $NAMESPACE

# Deploy or upgrade Helm release
helm upgrade --install sap-hana ../sap-hana-chart \
  --namespace $NAMESPACE \
  --wait

echo
echo "✅ SAP HANA deployment triggered."
echo "Checking pod status..."
kubectl get pods -n $NAMESPACE -w
