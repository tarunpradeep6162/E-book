az account show --query '{subscription:id,tenant:tenantId}'
az aks get-credentials --resource-group orders-platform-lab \
  --name orders-aks
kubectl config current-context
kubectl get nodes -o wide
kubectl auth can-i get pods -n orders
