FROM ubuntu:22.04

# ---- Tool versions ----
ARG KUBECTL_VER=1.30.5
ARG MINIKUBE_VER=latest

# ---- OS packages ----
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git make jq tar gzip unzip ca-certificates openssl \
    iproute2 iptables procps bash-completion \
    conntrack socat gnupg2 \
    systemd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Minikube ----
RUN curl -LO https://storage.googleapis.com/minikube/releases/${MINIKUBE_VER}/minikube-linux-amd64 && \
    install minikube-linux-amd64 /usr/local/bin/minikube && \
    rm minikube-linux-amd64

# ---- kubectl ----
RUN curl -LO "https://dl.k8s.io/release/v${KUBECTL_VER}/bin/linux/amd64/kubectl" && \
    install kubectl /usr/local/bin/kubectl && \
    rm kubectl

# ---- Required directories ----
RUN mkdir -p /var/lib/kubelet /var/lib/docker /var/run /sys/fs/cgroup && \
    chmod -R 0755 /var/lib/kubelet /var/lib/docker /var/run /sys/fs/cgroup

# ---- Workspace ----
RUN mkdir -p /workspace
WORKDIR /workspace

# ---- Startup script ----
COPY start-minikube.sh /usr/local/bin/start-minikube.sh
RUN chmod +x /usr/local/bin/start-minikube.sh

CMD ["/usr/local/bin/start-minikube.sh"]