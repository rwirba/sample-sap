CREATE CLUSTER

az provider register --namespace Microsoft.OperationalInsights

az aks get-credentials --resource-group rg-demo --name aks-demo-cluster 

if you hit error install python dependency with 

sudo dnf or apt install python3-cffi 

install nginx ingress controller

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.extraArgs.tcp-services-configmap="ingress-nginx/tcp-services" \
  --set controller.service.extraPorts[0].name=pgsql \
  --set controller.service.extraPorts[0].port=5432 \
  --set controller.service.extraPorts[0].targetPort=5432 \
  --set controller.service.extraPorts[0].protocol=TCP


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




If you want to keep building on this:

•  ✅ Add a readinessProbe to ensure traffic only hits healthy pods
•  ✅ Wire in TLS with cert-manager for secure ingress
•  ✅ Create a Service and Ingress to expose PostgreSQL (if needed)
•  ✅ Add volume snapshot support for backup/restore
•  ✅ Parameterize database name, user, and port in values.yaml



az aks get-credentials --resource-group rg-demo --name aks-demo-cluster 


kubectl run psql-test --image=postgres --rm -it --env="PGPASSWORD=StrongPassword123" -- \
  psql -h ingress-nginx-controller.ingress-nginx -p 5432 -U postgres


  kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

  run this to force patch to tcp
  kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/ports/-",
    "value": {
      "name": "pgsql",
      "port": 5432,
      "targetPort": 5432,
      "protocol": "TCP"
    }
  }
]'
