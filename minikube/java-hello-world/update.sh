#!/bin/bash
set -e

echo "Updating app in Minikube..."

helm upgrade hello-java . \
  --namespace demo 

# pkill -f "minikube tunnel"
# minikube tunnel --alsologtostderr -v=8