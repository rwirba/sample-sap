#!/bin/bash
set -e

export CONTAINERD_SNAPSHOTTER=fuse-overlayfs
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Starting K3s in foreground..."
exec k3s server --disable traefik --tls-san 127.0.0.1