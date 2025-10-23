#!/bin/bash
set -e

APP_NAME=$1
NAMESPACE="demo"

if [ -z "$APP_NAME" ]; then
  echo "❌ Usage: ./expose.sh <app-name>"
  echo "Example: ./expose.sh java-ads-demo"
  exit 1
fi

# Get Minikube IP
MINIKUBE_IP=$(minikube ip)

# Wait for service to exist
echo "⏳ Waiting for $APP_NAME service in '$NAMESPACE' namespace..."
until kubectl get svc $APP_NAME -n $NAMESPACE &> /dev/null; do sleep 2; done

# Extract NodePort dynamically
NODEPORT=$(kubectl get svc $APP_NAME -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')

# Add iptables rules only if they don't already exist
if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT} 2>/dev/null; then
  echo "🔧 Adding PREROUTING rule..."
  sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT}
else
  echo "✅ PREROUTING rule already exists."
fi

if ! sudo iptables -t nat -C POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE 2>/dev/null; then
  echo "🔧 Adding POSTROUTING rule..."
  sudo iptables -t nat -A POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE
else
  echo "✅ POSTROUTING rule already exists."
fi

# Determine hostname based on app name
if [[ "$APP_NAME" == *"ads"* ]]; then
  HOST="ads"
else
  HOST="hello"
fi

PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)

echo "🚀 Traffic to port 80 is now routed to NodePort ${NODEPORT} on Minikube IP ${MINIKUBE_IP}"
echo "Access your app via: http://${HOST}.${PUBLIC_IP}.nip.io/"