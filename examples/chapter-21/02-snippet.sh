export RECOVERY_CONTEXT=azure-recovery
kubectl --context "$RECOVERY_CONTEXT" -n data get pod postgres-0
kubectl --context "$RECOVERY_CONTEXT" -n data exec postgres-0 -- \
  psql -U orders_admin -d orders -v ON_ERROR_STOP=1 \
  -c "SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();"
