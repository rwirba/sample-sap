FROM registry.access.redhat.com/ubi9/ubi

# ---- Tool versions ----
ARG KUBECTL_VER=1.30.5
ARG HELM_VER=3.15.3
ARG TRIVY_VER=0.61.1
ARG KUBELOGIN_VER=0.0.33
ARG k8s_VER=v1.30.1+k8s1

# ---- OS packages ----
RUN dnf install -y --allowerasing \
    podman buildah skopeo fuse-overlayfs slirp4netns crun conmon \
    git make jq tar gzip unzip curl wget ca-certificates openssl \
    java-17-openjdk-devel maven \
    iproute iptables procps-ng \
    bash-completion shadow-utils && \
    dnf clean all

# ---- HashiCorp repo and Terraform ----
RUN curl -fsSL https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo -o /etc/yum.repos.d/hashicorp.repo && \
    dnf install -y terraform && \
    terraform -version

# ---- Azure CLI ----
# Add Microsoft repo and install Azure CLI
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc && \
    echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
    > /etc/yum.repos.d/azure-cli.repo && \
    dnf install -y azure-cli && \
    az version

# ---- kubectl ----
RUN curl -fsSL -o /usr/local/bin/kubectl \
    https://dl.k8s.io/release/v${KUBECTL_VER}/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl

# ---- helm ----
RUN curl -fsSL -o /tmp/helm.tgz https://get.helm.sh/helm-v${HELM_VER}-linux-amd64.tar.gz && \
    tar -xzf /tmp/helm.tgz -C /tmp && mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/helm.tgz /tmp/linux-amd64

# ---- trivy ----
RUN curl -fsSL -o /tmp/trivy.tgz \
    https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_Linux-64bit.tar.gz && \
    tar -xzf /tmp/trivy.tgz -C /usr/local/bin trivy && rm -f /tmp/trivy.tgz

# ---- kubelogin ----
RUN curl -fsSL -o /tmp/kubelogin.zip \
    https://github.com/Azure/kubelogin/releases/download/v${KUBELOGIN_VER}/kubelogin-linux-amd64.zip && \
    unzip -j /tmp/kubelogin.zip 'bin/linux_amd64/kubelogin' -d /usr/local/bin && \
    chmod +x /usr/local/bin/kubelogin && \
    rm -f /tmp/kubelogin.zip && \
    /usr/local/bin/kubelogin --version

# ---- aks & acr login
COPY aks-login.sh /usr/local/bin/aks-login.sh
COPY acr-login.sh /usr/local/bin/acr-login.sh
RUN chmod +x /usr/local/bin/aks-login.sh /usr/local/bin/acr-login.sh

RUN curl -fsSL https://github.com/k8s-io/k8s/releases/download/${k8s_VER}/k8s -o /usr/local/bin/k8s && \
    chmod +x /usr/local/bin/k8s && \
    mkdir -p /etc/rancher/k8s /var/lib/rancher/k8s /var/lib/kubelet /etc/kubernetes

COPY start-k3s.sh /usr/local/bin/start-k3s.sh
RUN chmod +x /usr/local/bin/start-k3s.sh


# ---- QoL ----
RUN mkdir -p /workspace && chmod 0777 /workspace
WORKDIR /workspace
CMD ["/usr/local/bin/start-k3s.sh"]    