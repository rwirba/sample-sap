## 🚀 Prerequisites for New Domain Setup

This guide outlines the steps required to prepare a new domain for Kubernetes-based demos using Minikube, Cloudflare Tunnel, and the `sample-sap` repository.

---

### 📁 1. Prepare Minikube Workspace

```bash
sudo mkdir -p /opt/minikube
sudo chown ec2-user:ec2-user /opt/minikube
cd /opt/minikube
sudo su - sapuser
git clone https://github.com/rwirba/sample-sap.git
cd sample-sap
git checkout k8s-automation
```

---

### 🌐 2. Create Cloudflare Tunnel

```bash
cloudflared tunnel create global-tunnel
```

This will generate a tunnel descriptor file at:
```
~/.cloudflared/<UUID>.json
```

Upload it to S3 for automation:

```bash
aws s3 cp ~/.cloudflared/685f93fc-fc7d-49cd-ae7a-231479572dbf.json s3://ryandevlab-bucket/cloudflare-tunnel.json
```

---

### 🔐 3. Authenticate Cloudflare Manually (One-Time)

```bash
cloudflared login
```

This will:
- Open a browser link (copy-paste into your browser if needed)
- Prompt you to select your domain: `ryandemolab.app`
- Download and save `cert.pem` to:
  ```
  /root/.cloudflared/cert.pem
  ```

Once authenticated, Cloudflare will generate a valid tunnel descriptor for automation.

---

### 📄 4. Create Metadata File for Automation Scripts

Create a simple metadata file that your automation scripts can consume:

```bash
cat <<EOF > metadata.txt
http://98.84.141.61:33871/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/
EOF
```

---

### 🔍 5. Validate Kubernetes Resources

```bash
kubectl -n demo get pods -o wide
kubectl -n demo get svc java-ads-demo -o wide
kubectl -n demo describe svc java-ads-demo | egrep 'Type:|Port:|TargetPort|NodePort|Endpoints'
kubectl -n demo get endpoints java-ads-demo
```

---

### 🌐 6. Test Service Exposure via NodePort

```bash
MINIKUBE_IP=$(minikube ip)
NODE_PORT=$(kubectl -n demo get svc java-ads-demo -o jsonpath='{.spec.ports[0].nodePort}')
curl -sv "http://${MINIKUBE_IP}:${NODE_PORT}"
```

---
for hana and vault


if ! command -v kubectl &>/dev/null; then
  echo "📦 Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

if ! command -v minikube &>/dev/null; then
  echo "📦 Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

if ! command -v helm &>/dev/null; then
  echo "📦 Installing Helm..."
  curl -LO https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
  tar -zxf helm-v3.13.1-linux-amd64.tar.gz >/dev/null
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz
fi

# ==============================================================
# ⚙️ MINIKUBE SETUP
# ==============================================================
HOST_CPUS=$(nproc)
HOST_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
REQ_CPUS=$(( HOST_CPUS > 6 ? 6 : (HOST_CPUS - 1) ))
REQ_MEM=$(( HOST_MEM > 18000 ? 16000 : (HOST_MEM - 2000) ))

sudo mkdir -p /data/minikube
sudo chown -R ec2-user:ec2-user /data/minikube
sudo chmod -R 777 /data/minikube

if ! minikube status | grep -q "host: Running"; then
  echo "🚀 Starting Minikube (Podman driver)..."
  minikube start \
    --driver=podman \
    --container-runtime=cri-o \
    --mount=true \
    --mount-string="/data/minikube:/var/lib/minikube" \
    --cpus="${REQ_CPUS}" \
    --memory="${REQ_MEM}" \
    --disk-size=50g \
    --force
else
  echo "✅ Minikube already running."
fi

kubectl wait --for=condition=Ready node --all --timeout=180s || true

helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard


kubectl create serviceaccount dashboard-admin-sa -n kubernetes-dashboard

kubectl create clusterrolebinding dashboard-admin-sa-binding --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:dashboard-admin-sa
kubectl -n kubernetes-dashboard create token dashboard-admin-sa

kubectl -n kubernetes-dashboard port-forward --address 0.0.0.0 svc/kubernetes-dashboard-kong-proxy 8443:443 &
