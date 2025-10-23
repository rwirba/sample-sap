#!/bin/bash
set -e

# Get Minikube IP
MINIKUBE_IP=$(minikube ip)

# Wait for service to exist
echo "⏳ Waiting for ads-java-demo service in 'demo' namespace..."
until kubectl get svc ads-java-demo -n demo &> /dev/null; do sleep 2; done

# Extract NodePort dynamically
NODEPORT=$(kubectl get svc ads-java-demo -n demo -o jsonpath='{.spec.ports[0].nodePort}')

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

echo "🚀 Traffic to port 80 is now routed to NodePort ${NODEPORT} on Minikube IP ${MINIKUBE_IP}"
echo "🌐 Access your app via: http://ads.$(curl -s http://checkip.amazonaws.com).nip.io/"