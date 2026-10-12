helm lint ./charts/orders-api
helm template orders-api ./charts/orders-api \
  -f values-prod.yaml > rendered.yaml
# Validate in the intended existing namespace and context.
kubectl apply --dry-run=server -f rendered.yaml
helm upgrade --install orders-api ./charts/orders-api \
  --namespace orders -f values-prod.yaml \
  --wait --timeout 5m --atomic
