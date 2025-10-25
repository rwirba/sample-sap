#!/bin/bash
set -e

echo "Updating app in Minikube..."

helm upgrade hello-java ./java-hello-world-chart \
  --namespace demo 

# pkill -f "minikube tunnel"
# minikube tunnel --alsologtostderr -v=8