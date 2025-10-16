#!/bin/bash
set -e

export MINIKUBE_HOME=/root
export CHANGE_MINIKUBE_NONE_USER=true

echo "Starting Minikube..."
minikube start --driver=none --force --kubernetes-version=v1.30.1

echo "Waiting for cluster..."
until kubectl get nodes &>/dev/null; do sleep 2; done

kubectl get nodes
kubectl get pods -A

# Keep container alive
tail -f /dev/null