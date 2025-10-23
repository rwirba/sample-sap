#!/bin/bash
set -e

echo "🚀 Deploying Java Hello World app to Minikube..."

# Create namespace if missing
kubectl get ns demo &> /dev/null || kubectl create ns demo

# Deploy Helm chart using values.yaml + dynamic ingress host
helm upgrade --install hello-java ./helm-chart \
  --namespace demo \
  --set ingress.host=$(curl -s http://checkip.amazonaws.com).nip.io \
  --wait

# Ensure minikube tunnel is running
if ! pgrep -f "minikube tunnel" > /dev/null; then
  echo "🔌 Starting minikube tunnel in background..."
  nohup sudo minikube tunnel > /dev/null 2>&1 &
else
  echo "✅ Minikube tunnel is already running."
fi

echo "✅ App deployed. Access it at: http://$(curl -s http://checkip.amazonaws.com).nip.io/"