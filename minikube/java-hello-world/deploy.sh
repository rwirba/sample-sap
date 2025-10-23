#!/bin/bash
set -e

echo "🚀 Deploying Java Hello World app to Minikube..."

# Build image if not present
if ! podman image exists java-hello-world:latest; then
  echo "🛠️ Building Podman image..."
  podman build -t java-hello-world:latest .
fi

# Load image into Minikube
echo "📦 Loading image into Minikube..."
minikube image load java-hello-world:latest

# Create namespace if missing
kubectl get ns demo || kubectl create ns demo

# Deploy Helm chart
helm upgrade --install hello-java ./helm-chart \
  --namespace demo \
  --set image.repository=java-hello-world \
  --set ingress.host=$(curl -s http://checkip.amazonaws.com) \
  --wait

# Start tunnel if not running
if ! pgrep -f "minikube tunnel" > /dev/null; then
  echo "🔌 Starting minikube tunnel in background..."
  nohup minikube tunnel > /dev/null 2>&1 &
fi

echo "✅ App deployed. Access it at: http://$(curl -s http://checkip.amazonaws.com)/"