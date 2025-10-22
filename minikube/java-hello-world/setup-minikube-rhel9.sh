#!/usr/bin/env bash
# ============================================================
#  RHEL 9 / EC2  —  Automated Setup for Minikube (--driver=none)
# ============================================================
set -euo pipefail

# -------------------------------
# Versions
# -------------------------------
CRI_DOCKERD_VER="v0.3.20"
CNI_VER="v1.5.1"
MINIKUBE_VER="v1.37.0"

# -------------------------------
# Base Tools
# -------------------------------
echo "🧩 Installing base packages..."
dnf install -y curl wget tar conntrack iptables git vim socat \
    libnetfilter_cthelper libnetfilter_cttimeout libnetfilter_queue || true

# -------------------------------
# Docker (Community Edition)
# -------------------------------
echo "🐳 Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io || true
  systemctl enable --now docker
fi

# -------------------------------
# cri-dockerd
# -------------------------------
echo "🔧 Installing cri-dockerd..."
cd /tmp
curl -L -o cri-dockerd-${CRI_DOCKERD_VER}-linux-amd64.tar.gz \
  https://github.com/Mirantis/cri-dockerd/releases/download/${CRI_DOCKERD_VER}/cri-dockerd-${CRI_DOCKERD_VER#v}-linux-amd64.tar.gz
tar -C /usr/local/bin -xzf cri-dockerd-${CRI_DOCKERD_VER}-linux-amd64.tar.gz
if [ -d /usr/local/bin/cri-dockerd ]; then
  mv /usr/local/bin/cri-dockerd/cri-dockerd /usr/local/bin/
  rm -rf /usr/local/bin/cri-dockerd
fi
chmod +x /usr/local/bin/cri-dockerd

# -------------------------------
# systemd unit files
# -------------------------------
echo "⚙️  Creating systemd units..."
cat >/etc/systemd/system/cri-docker.service <<'EOF'
[Unit]
Description=CRI Interface for Docker
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.socket

[Service]
Type=notify
ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd://
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/cri-docker.socket <<'EOF'
[Unit]
Description=CRI Docker Socket for the API
PartOf=cri-docker.service

[Socket]
ListenStream=/var/run/cri-dockerd.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

systemctl daemon-reload
setenforce 0 || true
systemctl enable --now cri-docker.socket cri-docker.service
mkdir -p /etc/cni/net.d

# -------------------------------
# CNI Plugins
# -------------------------------
echo "🌐 Installing CNI plugins..."
mkdir -p /opt/cni/bin
curl -L -o cni-plugins-linux-amd64-${CNI_VER}.tgz \
  https://github.com/containernetworking/plugins/releases/download/${CNI_VER}/cni-plugins-linux-amd64-${CNI_VER}.tgz
tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-${CNI_VER}.tgz

# -------------------------------
# Minikube & kubectl
# -------------------------------
echo "📦 Installing Minikube ${MINIKUBE_VER} and kubectl..."
curl -Lo /usr/local/bin/minikube \
  https://storage.googleapis.com/minikube/releases/${MINIKUBE_VER}/minikube-linux-amd64
chmod +x /usr/local/bin/minikube
curl -Lo /usr/local/bin/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.34.0/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl

# -------------------------------
# Verification
# -------------------------------
echo "✅ Setup complete!"
echo "Run 'minikube start --driver=none' to launch your cluster."
