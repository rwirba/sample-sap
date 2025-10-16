#!/bin/bash
set -e

echo "Starting K3s with fuse-overlayfs..."
export CONTAINERD_SNAPSHOTTER=fuse-overlayfs
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

k3s server --disable traefik --tls-san 127.0.0.1 &

echo "Waiting for Kubernetes API to be ready..."
until kubectl get nodes &>/dev/null; do
  sleep 2
done

kubectl get nodes
kubectl get pods -A

exec /bin/bash