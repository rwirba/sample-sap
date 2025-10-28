#!/bin/bash
set -e

echo "Updating Ads app in Minikube..."
helm upgrade ads-demo ./java-ads-chart --namespace demo
