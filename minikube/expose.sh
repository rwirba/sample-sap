#!/bin/bash

NODEPORT=30393
MINIKUBE_IP=$(minikube ip)

echo "Waiting for ingress-nginx-controller service..."

# Flush old rules (optional but clean)
sudo iptables -t nat -D PREROUTING -p tcp --dport 80 -j DNAT --to-destination $MINIKUBE_IP:$NODEPORT 2>/dev/null
sudo iptables -t nat -D POSTROUTING -p tcp -d $MINIKUBE_IP --dport $NODEPORT -j MASQUERADE 2>/dev/null

# Apply new rules
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $MINIKUBE_IP:$NODEPORT
sudo iptables -t nat -A POSTROUTING -p tcp -d $MINIKUBE_IP --dport $NODEPORT -j MASQUERADE

echo "Traffic to port 80 is now routed to Ingress NodePort ${NODEPORT} on Minikube IP ${MINIKUBE_IP}"
echo "Access your apps via:"
echo "  - http://hello.$(curl -s http://checkip.amazonaws.com).nip.io/"
echo "  - http://ads.$(curl -s http://checkip.amazonaws.com).nip.io/"