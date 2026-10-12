kubectl config current-context
docker ps --format '{{.Names}}'
export LAB_WORKER=REPLACE_OBSERVED_KIND_WORKER
# After verifying that this is the approved disposable worker:
docker stop "$LAB_WORKER"
kubectl get nodes
kubectl -n orders get pods -o wide
# Independent rollback:
docker start "$LAB_WORKER"
