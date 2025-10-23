#!/bin/bash
set -e

echo "🚀 Deploying Java Hello World app to Minikube..."

# Create namespace if missing
kubectl get ns demo &> /dev/null || kubectl create ns demo

# Deploy Helm chart using public Docker Hub image
helm upgrade --install hello-java .\
  --namespace demo \
  --set image.repository=ryandevlab/java-hello-world \
  --set image.tag=1.0.0 \
  --set ingress.host=$(curl -s http://checkip.amazonaws.com) \
  --wait

# Start tunnel if not running
if ! pgrep -f "minikube tunnel" > /dev/null; then
  echo "🔌 Starting minikube tunnel in background..."
  nohup minikube tunnel > /dev/null 2>&1 &
fi

echo "✅ App deployed. Access it at: http://$(curl -s http://checkip.amazonaws.com)/"
#