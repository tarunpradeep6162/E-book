kubectl config current-context
kubectl apply --dry-run=server -f namespace.yaml
kubectl apply -f namespace.yaml
kubectl apply --dry-run=server -f deployment.yaml -f service.yaml
kubectl apply -f deployment.yaml -f service.yaml
kubectl -n orders rollout status deployment/orders-api --timeout=120s
kubectl -n orders get pods -o wide
kubectl -n orders get endpointslices
