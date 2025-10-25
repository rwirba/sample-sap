#!/bin/bash
set -euo pipefail

NAMESPACE="demo"
RELEASE_NAME="mysql-db"

echo "🚀 Deploying MySQL Helm chart..."
kubectl create ns $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install $RELEASE_NAME ./mysql-chart \
  --namespace $NAMESPACE --wait

kubectl get pods -n $NAMESPACE | grep mysql
kubectl get svc -n $NAMESPACE | grep mysql

echo "✅ MySQL deployed successfully."
