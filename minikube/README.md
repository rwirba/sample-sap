

Absolutely, Shey — here’s a polished and professional version of your README that clearly documents the prerequisites and setup steps for onboarding a new domain with Minikube, Cloudflare Tunnel, and your demo app:

---

## 🚀 Prerequisites for New Domain Setup

This guide outlines the steps required to prepare a new domain for Kubernetes-based demos using Minikube, Cloudflare Tunnel, and the `sample-sap` repository.

---

### 📁 1. Prepare Minikube Workspace

```bash
sudo mkdir -p /opt/minikube
sudo chown ec2-user:ec2-user /opt/minikube
cd /opt/minikube
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

Let me know if you'd like to add Helm install steps, automate the Cloudflare tunnel creation, or wrap this into a full onboarding script. I can also help you version this README for multiple environments or demo tiers.