
#  Local Kubernetes Demo Setup (Minikube + Podman Desktop)

This guide walks you through setting up a fully functional Kubernetes cluster using Minikube on **macOS**, **Windows**, or **Podman Desktop**, with ingress routing, sample apps, and 404 fallback 

---

##  macOS Setup (Minikube + Docker)

###  Prerequisites

1. **Install Homebrew**:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. **Install Docker Desktop**  
   [Download here](https://www.docker.com/products/docker-desktop)

3. **Install Minikube and kubectl**:
   ```bash
   brew install minikube kubectl
   ```

---

##  Windows Setup (Minikube + Docker Desktop)

###  Prerequisites

1. **Install Docker Desktop**  
   [Download here](https://www.docker.com/products/docker-desktop)

2. **Install Chocolatey**:
   Open PowerShell as Administrator:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
   ```

3. **Install Minikube and kubectl**:
   ```powershell
   choco install minikube kubernetes-cli -y
   ```

---

##  macOS Setup (Minikube + Podman Desktop)

###  Prerequisites

1. **Install Podman Desktop**  
   [Download here](https://podman.io/getting-started/installation)

2. **Install Minikube and kubectl**:
   ```bash
   brew install minikube kubectl
   ```

3. **Start Podman VM** (required for Linux container runtime):
   ```bash
   podman machine init
   podman machine start
   ```

4. **Start Minikube with Podman driver**:
   ```bash
   minikube start --driver=podman --kubernetes-version=v1.30.1
   ```

---

##  Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

Expected output:
- Node status: `Ready`
- System pods: `Running`

---

##  Enable Ingress

```bash
minikube addons enable ingress
```

---

##  Deploy Sample Apps

###  hello-world

```bash
kubectl create deployment hello-world --image=k8s.gcr.io/echoserver:1.4
kubectl expose deployment hello-world --port=8080 --target-port=8080 --name=hello-world
```

###  java-ads

```bash
kubectl create deployment java-ads --image=nginxdemos/hello
kubectl expose deployment java-ads --port=80 --target-port=80 --name=java-ads
```

---

##  Ingress with Host-Based Routing + 404 Fallback

###  Create `demo-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  annotations:
    nginx.ingress.kubernetes.io/default-backend: hello-world
spec:
  rules:
  - host: hello.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-world
            port:
              number: 8080
  - host: ads.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: java-ads
            port:
              number: 80
```

Apply it:
```bash
kubectl apply -f demo-ingress.yaml
```

---

##  Add Hosts Entry

Edit your hosts file:

- **macOS**: `/etc/hosts`
- **Windows**: `C:\Windows\System32\drivers\etc\hosts`

Add:
```
127.0.0.1 hello.local ads.local
```

---

##  Test Routing

```bash
curl http://hello.local
curl http://ads.local
curl http://unknown.local  # Should return 404 or default backend
```

---

##  Optional: TLS with cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.1 \
  --set installCRDs=true
```

---

##  Reset Cluster

```bash
minikube delete
minikube start --driver=podman
```

---

## You're Demo-Ready!

You now have:
- A working Kubernetes cluster
- Ingress routing with host-based rules
- Sample apps deployed
- 404 fallback and optional TLS support

```

