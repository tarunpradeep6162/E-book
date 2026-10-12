kubectl -n backend get networkpolicy
kubectl -n backend describe networkpolicy allow-frontend-to-api
kubectl -n backend get pods --show-labels
kubectl get namespaces --show-labels
