kubectl --context "$RECOVERY_CONTEXT" -n data exec postgres-0 -- \
  gosu postgres pg_ctl \
  -D /var/lib/postgresql/data/pgdata promote -w -t 60

kubectl --context "$RECOVERY_CONTEXT" -n data exec postgres-0 -- \
  psql -U orders_admin -d orders -v ON_ERROR_STOP=1 \
  -c "SELECT pg_is_in_recovery();"
