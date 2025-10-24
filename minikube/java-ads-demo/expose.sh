#!/bin/bash
set -e

MINIKUBE_IP=$(minikube ip)

echo "Waiting for java-ads-demo service in 'demo' namespace..."
until kubectl get svc java-ads-demo -n demo &> /dev/null; do sleep 2; done

NODEPORT=$(kubectl get svc java-ads-demo -n demo -o jsonpath='{.spec.ports[0].nodePort}')

echo "Access your Ads app via: http://ads.${MINIKUBE_IP}.nip.io/"
