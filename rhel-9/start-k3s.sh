#!/bin/bash
set -e

export CONTAINERD_SNAPSHOTTER=fuse-overlayfs
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Starting K3s with user namespace support..."
exec k3s server \
  --disable traefik \
  --tls-san 127.0.0.1 \
  --kubelet-arg="feature-gates=KubeletInUserNamespace=true"