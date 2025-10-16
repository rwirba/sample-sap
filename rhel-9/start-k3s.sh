#!/bin/bash
set -e

echo "Starting K3s with fuse-overlayfs..."
export CONTAINERD_SNAPSHOTTER=fuse-overlayfs

k3s server --disable traefik --tls-san 127.0.0.1 &

sleep 5
echo "Waiting for Kubernetes API to be ready..."
kubectl get nodes || true

exec /bin/bash