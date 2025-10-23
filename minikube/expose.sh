#!/bin/bash

echo "🔍 Detecting Ingress NodePort for port 80..."

# Get Minikube IP
MINIKUBE_IP=$(minikube ip)

# Get the NodePort for port 80 from the ingress-nginx-controller service
NODEPORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

if [ -z "$NODEPORT" ]; then
  echo "❌ Failed to detect NodePort for ingress-nginx-controller"
  exit 1
fi

echo "✅ Found NodePort: $NODEPORT"
echo "🔄 Applying iptables rules..."

# Flush old rules (optional)
sudo iptables -t nat -D PREROUTING -p tcp --dport 80 -j DNAT --to-destination $MINIKUBE_IP:$NODEPORT 2>/dev/null
sudo iptables -t nat -D POSTROUTING -p tcp -d $MINIKUBE_IP --dport $NODEPORT -j MASQUERADE 2>/dev/null

# Apply new rules
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $MINIKUBE_IP:$NODEPORT
sudo iptables -t nat -A POSTROUTING -p tcp -d $MINIKUBE_IP --dport $NODEPORT -j MASQUERADE

echo "🚀 Traffic to EC2 port 80 is now routed to Minikube Ingress NodePort $NODEPORT"
echo "Access your apps via:"
echo "  - http://hello.$(curl -s http://checkip.amazonaws.com).nip.io/"
echo "  - http://ads.$(curl -s http://checkip.amazonaws.com).nip.io/"