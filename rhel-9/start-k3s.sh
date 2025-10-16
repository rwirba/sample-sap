#!/bin/bash
set -e

export CONTAINERD_SNAPSHOTTER=fuse-overlayfs
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Starting K3s with container-safe kubelet args..."
exec k3s server \
  --disable traefik \
  --tls-san 127.0.0.1 \
  --kubelet-arg="feature-gates=KubeletInUserNamespace=true" \
  --kubelet-arg="cgroups-per-qos=false" \
  --kubelet-arg="cgroup-root=/" \
  --kubelet-arg="enforce-node-allocatable=" \
  --kubelet-arg="runtime-cgroups=" \
  --kubelet-arg="kubelet-cgroups=" \
  --kubelet-arg="systemd-cgroup=false"