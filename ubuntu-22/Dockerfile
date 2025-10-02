FROM ubuntu:22.04

# ---- Tool versions ----
ARG KUBECTL_VER=1.30.5
ARG HELM_VER=3.15.3
ARG TRIVY_VER=0.51.4
ARG KUBELOGIN_VER=0.0.33

# ---- OS packages ----
RUN apt-get update && apt-get install -y \
    podman buildah skopeo fuse-overlayfs slirp4netns crun conmon \
    git make jq tar gzip unzip curl wget ca-certificates openssl \
    openjdk-17-jdk maven \
    iproute2 iptables procps \
    bash-completion \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Azure CLI ----
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

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

# ---- aks-login.sh ----
RUN cat > /usr/local/bin/aks-login.sh <<'EOS' && chmod +x /usr/local/bin/aks-login.sh
#!/usr/bin/env bash
set -euo pipefail
if ! az account show >/dev/null 2>&1; then
  echo "[aks-login] Launching device-code login..."
  az login --use-device-code >/dev/null
fi
: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${AKS_NAME:?Set AKS_NAME}"
az account set -s "$SUBSCRIPTION_ID"
echo "[aks-login] Fetching kubeconfig for $AKS_NAME ..."
az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKS_NAME" --overwrite-existing
echo "[aks-login] Converting kubeconfig for kubelogin (azurecli mode) ..."
kubelogin convert-kubeconfig -l azurecli
kubectl cluster-info
kubectl get nodes -o wide
EOS

# ---- acr-login.sh ----
RUN cat > /usr/local/bin/acr-login.sh <<'EOS' && chmod +x /usr/local/bin/acr-login.sh
#!/usr/bin/env bash
set -euo pipefail
: "${ACR_NAME:?Set ACR_NAME (e.g., myregistry)}"
LOGIN_SERVER="${ACR_NAME}.azurecr.io"
echo "[acr-login] Getting access token for $LOGIN_SERVER ..."
TOKEN="$(az acr login -n "$ACR_NAME" --expose-token --output tsv --query accessToken)"
podman login "$LOGIN_SERVER" -u 00000000-0000-0000-0000-000000000000 -p "$TOKEN"
echo "[acr-login] Podman is logged into $LOGIN_SERVER"
EOS

# ---- QoL ----
RUN mkdir -p /workspace && chmod 0777 /workspace
WORKDIR /workspace
