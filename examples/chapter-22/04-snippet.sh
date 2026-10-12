kubectl apply --dry-run=server -f deny-database-egress.yaml
kubectl apply -f deny-database-egress.yaml
kubectl -n gameday logs deployment/orders-api --tail=100
# Roll back only this experiment's policy.
kubectl -n gameday delete networkpolicy experiment-deny-database
