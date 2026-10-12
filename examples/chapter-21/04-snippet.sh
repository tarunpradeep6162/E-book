# recovery/ contains complete reviewed Azure-specific manifests, not snippets.
kubectl --context "$RECOVERY_CONTEXT" apply --dry-run=server -f recovery/
kubectl --context "$RECOVERY_CONTEXT" apply -f recovery/
kubectl --context "$RECOVERY_CONTEXT" -n orders \
  rollout status deployment/orders-api --timeout=180s
