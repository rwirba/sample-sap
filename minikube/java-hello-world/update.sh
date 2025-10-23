#!/bin/bash
set -e

echo "🔁 Updating app in Minikube..."

# Upgrade Helm release
helm upgrade hello-java . \
  --namespace demo \
  --set image.repository=ryandevlab/java-hello-world \
  --set image.tag=1.0.0 \
  --set service.type=LoadBalancer \
  --set service.port=80 \
  --set service.targetPort=8080 \
  --set ingress.host=$(curl -s http://checkip.amazonaws.com).nip.io \
  --wait

# Ensure minikube tunnel is running
if ! pgrep -f "minikube tunnel" > /dev/null; then
  echo "🔌 Starting minikube tunnel in background..."
  nohup sudo minikube tunnel > /dev/null 2>&1 &
else
  echo "✅ Minikube tunnel is already running."
fi

echo "✅ Update complete. App refreshed at: http://$(curl -s http://checkip.amazonaws.com).nip.io/"