#!/bin/bash
set -e

echo "Deploying Java Hello World app to Minikube..."

# Create namespace if missing
kubectl get ns demo &> /dev/null || kubectl create ns demo

# Deploy Helm chart using values.yaml + dynamic ingress host
helm upgrade --install hello-java ./java-hello-world-chart \
  --namespace demo \
  --wait
