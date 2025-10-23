#!/bin/bash
set -e

echo "Deploying ads-java-demo to Kubernetes..."

# Create namespace if it doesn't exist
kubectl get namespace demo &> /dev/null || kubectl create namespace demo

# Deploy using Helm
helm install ads-java ./ads-java-chart --namespace demo

echo "ads-java-demo deployed successfully."