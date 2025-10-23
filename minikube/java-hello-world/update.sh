#!/bin/bash
set -e

echo "🔁 Updating app in Minikube..."

# Upgrade Helm release using values.yaml + dynamic ingress host
helm upgrade hello-java . \
  --namespace demo 

# pkill -f "minikube tunnel"
# minikube tunnel --alsologtostderr -v=8