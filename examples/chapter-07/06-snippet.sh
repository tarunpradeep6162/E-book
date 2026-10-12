docker compose exec -T db createdb \
  -U orders_admin orders_restore_test
docker compose exec -T db pg_restore \
  -U orders_admin -d orders_restore_test \
  --exit-on-error --no-owner < backups/orders.dump
docker compose exec -T db psql \
  -U orders_admin -d orders_restore_test \
  -c "SELECT * FROM survival_test;"
