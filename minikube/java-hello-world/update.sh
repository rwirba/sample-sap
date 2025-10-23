#!/bin/bash
set -e

echo "🔁 Updating app in Minikube..."

# Rebuild image
podman build -t java-hello-world:latest .

# Reload into Minikube
minikube image load java-hello-world:latest

# Upgrade Helm release
helm upgrade hello-java ./helm-chart \
  --namespace demo \
  --set image.repository=java-hello-world \
  --set ingress.host=$(curl -s http://checkip.amazonaws.com) \
  --wait

echo "✅ Update complete. App refreshed at: http://$(curl -s http://checkip.amazonaws.com)/"