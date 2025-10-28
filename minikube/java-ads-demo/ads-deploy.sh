#!/bin/bash
set -e

echo "Deploying Java Ads Demo app to Minikube..."

kubectl get ns demo &> /dev/null || kubectl create ns demo

helm upgrade --install ads-demo ./java-ads-chart \
  --namespace demo \
  --wait
