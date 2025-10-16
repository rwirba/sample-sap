
# AKS Toolkit with Podman, Helm, and Azure ACR

This guide walks through building a containerized AKS toolkit using Podman, pushing images to Azure Container Registry (ACR), and deploying to Azure Kubernetes Service (AKS).

---

##  Build Base Image

```bash
podman build -t k1:rhel9 .
```

---

##  Create Persistent Volumes

```bash
# General volumes
podman volume create k1-containers
podman volume create k1-workspace
podman volume create k1-trivy
podman volume create k1-m2
podman volume create k1-kube
podman volume create k1-azure
podman volume create k1-dbdata

# AKS Toolkit volumes
podman volume create aks-toolkit-containers
podman volume create aks-toolkit-workspace
podman volume create aks-toolkit-trivy
podman volume create aks-toolkit-m2
podman volume create aks-toolkit-kube
podman volume create aks-toolkit-azure
podman volume create aks-toolkit-dbdata
podman volume create terraform-state
```

---

##  Run AKS Toolkit Container

### Ubuntu-based

```bash
podman run -d --name aks-toolkit --hostname aks-toolkit \
  --privileged --network host \
  -v aks-toolkit-containers:/var/lib/containers \
  -v aks-toolkit-workspace:/workspace \
  -v aks-toolkit-trivy:/root/.cache/trivy \
  -v aks-toolkit-m2:/root/.m2 \
  -v aks-toolkit-kube:/root/.kube \
  -v aks-toolkit-azure:/root/.azure \
  -v aks-toolkit-dbdata:/data \
  --entrypoint /usr/bin/sleep \
  aks-toolkit:latest infinity
```

### RHEL 9-based

```bash
podman build -t aks-toolkit:rhel .

podman run -d --name aks-toolkit --hostname aks-toolkit \
  --privileged --network host \
  -v aks-toolkit-containers:/var/lib/containers \
  -v aks-toolkit-workspace:/workspace \
  -v aks-toolkit-trivy:/root/.cache/trivy \
  -v aks-toolkit-m2:/root/.m2 \
  -v aks-toolkit-kube:/root/.kube \
  -v aks-toolkit-azure:/root/.azure \
  -v aks-toolkit-dbdata:/data \
  -v terraform-state:/workspace/state \
  --entrypoint /usr/bin/sleep \
  aks-toolkit:rhel infinity
```

---

## 🛠️ Enter the Container

```bash
podman exec -it aks-toolkit bash
```

---

## Verify Tool Versions

```bash
kubelogin --version
az --version | head -n 3
kubectl version --client --output=yaml | grep gitVersion
helm version
trivy --version
```

---

##  Build Application Images

Run the following scripts inside the container:

```bash
./build_java.sh
./build_hanna.sh
```

---

##  Authenticate with Azure & ACR

```bash
az account show >/dev/null 2>&1 || az login --use-device-code

az acr create --resource-group aks-demo-rg --name aksdemoacr3 --sku Basic
az acr login --name aksdemoacr3

export ACR_NAME=aksdemoacr3
TOKEN=$(az acr login -n "$ACR_NAME" --expose-token -o tsv --query accessToken)

podman login ${ACR_NAME}.azurecr.io \
  -u 00000000-0000-0000-0000-000000000000 -p "$TOKEN"
```

---

##  Tag Images for ACR

```bash
# dev
podman tag localhost/java-ads-demo:0.1  ${ACR_NAME}.azurecr.io/dev/java-ads-demo:0.1
podman tag localhost/hana-standin:0.1   ${ACR_NAME}.azurecr.io/dev/hana-standin:0.1

# demo
podman tag localhost/java-ads-demo:0.1  ${ACR_NAME}.azurecr.io/demo/java-ads-demo:0.1
podman tag localhost/hana-standin:0.1   ${ACR_NAME}.azurecr.io/demo/hana-standin:0.1
```

---

##  Push Images to ACR

```bash
podman push ${ACR_NAME}.azurecr.io/dev/java-ads-demo:0.1
podman push ${ACR_NAME}.azurecr.io/dev/hana-standin:0.1
podman push ${ACR_NAME}.azurecr.io/demo/java-ads-demo:0.1
podman push ${ACR_NAME}.azurecr.io/demo/hana-standin:0.1
```

---

##  Verify ACR Upload

```bash
az acr repository list -n ${ACR_NAME} -o table

az acr repository show-tags -n ${ACR_NAME} --repository dev/java-ads-demo -o table
az acr repository show-tags -n ${ACR_NAME} --repository dev/hana-standin -o table
```

---

## Create AKS Cluster

```bash
az provider register --namespace Microsoft.OperationalInsights

az aks create \
  --resource-group aks-demo-rg \
  --name aks-demo-cluster \
  --node-count 2 \
  --node-vm-size Standard_B2s \
  --generate-ssh-keys \
  --attach-acr aksdemoacr3
```

---

##  Deploy Helm Charts

```bash
helm install sap4hana sap4hana-chart --namespace demo
helm install java4adobe java4adobe-chart --namespace dev
```

---

##  Inspect Cluster Resources

```bash
kubectl get pods -n demo
kubectl get pods -n dev
kubectl get svc -n demo
kubectl get svc -n dev
kubectl get ingress -A

kubectl logs <pod-name> -n demo
```

---

##  Local PostgreSQL Test (Optional)

```bash
podman run -d --network=host -e POSTGRES_PASSWORD=demo123 hana-standin:0.1
```

---

## 
 Cleanup

az aks delete --name aks-demo-cluster --resource-group aks-demo-rg --yes --no-wait

az acr repository delete --name aksdemoacr3 --repository demo/hana-standin --yes
az acr repository delete --name aksdemoacr3 --repository dev/java-ads-demo --yes

az acr delete --name aksdemoacr3 --resource-group aks-demo-rg
```

---
```
