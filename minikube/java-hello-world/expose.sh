#!/bin/bash
set -e

APP_NAME="java-hello-world"
NAMESPACE="demo"
EXTERNAL_PORT=80

echo "⏳ Waiting for service '$APP_NAME' in namespace '$NAMESPACE'..."
until kubectl get svc "$APP_NAME" -n "$NAMESPACE" &> /dev/null; do sleep 2; done

MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')

if [ -z "$NODEPORT" ]; then
  echo "❌ Service '$APP_NAME' does not expose a NodePort."
  exit 1
fi

if ! sudo iptables -t nat -C PREROUTING -p tcp --dport $EXTERNAL_PORT -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT} 2>/dev/null; then
  echo "🔧 Adding PREROUTING rule..."
  sudo iptables -t nat -A PREROUTING -p tcp --dport $EXTERNAL_PORT -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT}
else
  echo "✅ PREROUTING rule already exists."
fi

if ! sudo iptables -t nat -C POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE 2>/dev/null; then
  echo "🔧 Adding POSTROUTING rule..."
  sudo iptables -t nat -A POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE
else
  echo "✅ POSTROUTING rule already exists."
fi

PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
echo "🚀 Port $EXTERNAL_PORT is now routed to NodePort ${NODEPORT} on Minikube IP ${MINIKUBE_IP}"
echo "🌐 Access your app via: http://ads.${PUBLIC_IP}.nip.io/"