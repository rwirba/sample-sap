#!/bin/bash
set -e

export CONTAINERD_SNAPSHOTTER=fuse-overlayfs
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Starting K3s..."
k3s server --disable traefik --tls-san 127.0.0.1 &

echo "Waiting for Kubernetes API..."
until kubectl get nodes &>/dev/null; do sleep 2; done

kubectl get nodes
kubectl get pods -A

# Keep container alive
tail -f /dev/null