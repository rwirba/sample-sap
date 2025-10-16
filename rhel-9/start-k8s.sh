#!/bin/bash
set -e
k3s server --disable traefik --tls-san 127.0.0.1 &
sleep 5
kubectl get nodes
exec /bin/bash