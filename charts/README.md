CREATE CLUSTER

az provider register --namespace Microsoft.OperationalInsights

az aks get-credentials --resource-group rg-demo --name aks-demo-cluster 

if you hit error install python dependency with 

sudo dnf or apt install python3-cffi 

install nginx ingress controller

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer


run command to find out the external ip of the ingress-controller
kubectl get svc ingress-nginx-controller -n ingress-nginx

kubectl create namespace demo

helm install sap4hana sap4hana-chart --namespace demo
helm install java4adobe java4adobe-chart --namespace dev  

kubectl get pods -n demo
kubectl get pods -n dev
kubectl get svc -n demo
kubectl get svc -n dev
kubectl get ingress -A 

kubectl logs sap4hanna-chart-6586d6577c-rzb5q -n demo 

kubectl create secret generic s4hanna-secret \
  --namespace demo \
  --from-literal=POSTGRES_PASSWORD=StrongPassword123



some errors you might run into

helm upgrade s4hanna . --namespace demo
Error: UPGRADE FAILED: failed to create resource: admission webhook "validate.nginx.ingress.kubernetes.io" denied the request: host "sap4hanna.mitechnology.org" and path "/" is already defined in ingress demo/sap4hanna-chart-ingress
[root@aks-toolkit sap4hanna]# kubectl delete ingress sap4hanna-chart-ingress -n demo
