#!/bin/bash
set -e

MINIKUBE_IP=$(minikube ip)

echo "Waiting for ingress-nginx-controller service..."
until kubectl get svc ingress-nginx-controller -n ingress-nginx &> /dev/null; do sleep 2; done

NODEPORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT} 2>/dev/null; then
  echo "Adding PREROUTING rule..."
  sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT}
else
  echo "PREROUTING rule already exists."
fi

if ! sudo iptables -t nat -C POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE 2>/dev/null; then
  echo "Adding POSTROUTING rule..."
  sudo iptables -t nat -A POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE
else
  echo "POSTROUTING rule already exists."
fi

echo "Traffic to port 80 is now routed to Ingress NodePort ${NODEPORT} on Minikube IP ${MINIKUBE_IP}"
echo "Access your apps via:"
echo "  - http://hello.$(curl -s http://checkip.amazonaws.com).nip.io/"
echo "  - http://ads.$(curl -s http://checkip.amazonaws.com).nip.io/"