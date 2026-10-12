kubectl -n data get statefulsets,pods,pvc
kubectl get pv
kubectl -n data describe pod postgres-0
kubectl -n data describe pvc data-postgres-0
