#!/bin/bash
set -e

echo "🔁 Updating app in Minikube..."

# Upgrade Helm release using values.yaml + dynamic ingress host
helm upgrade hello-java . \
  --namespace demo 

# Ensure minikube tunnel is running
if ! pgrep -f "minikube tunnel" > /dev/null; then
  echo "🔌 Starting minikube tunnel in background..."
  nohup sudo minikube tunnel > /dev/null 2>&1 &
else
  echo "✅ Minikube tunnel is already running."
fi

echo "✅ Update complete. App refreshed at: http://$(curl -s http://checkip.amazonaws.com).nip.io/"