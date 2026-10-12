aws eks update-kubeconfig --region ap-south-1 \
  --name orders-platform
kubectl config current-context
kubectl auth can-i get pods -n orders
kubectl get nodes -o wide
kubectl -n kube-system get pods
