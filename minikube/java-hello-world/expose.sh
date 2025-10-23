#!/bin/bash
set -e

MINIKUBE_IP=$(minikube ip)

echo "Waiting for ingress-nginx-controller service..."
until kubectl get svc ingress-nginx-controller -n ingress-nginx &> /dev/null; do sleep 2; done

NODEPORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

if ! sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT} 2>/dev/null; then
  sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${NODEPORT}
fi

if ! sudo iptables -t nat -C POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE 2>/dev/null; then
  sudo iptables -t nat -A POSTROUTING -p tcp -d ${MINIKUBE_IP} --dport ${NODEPORT} -j MASQUERADE
fi

echo "Access ads app via: http://ads.$(curl -s http://checkip.amazonaws.com).nip.io/"