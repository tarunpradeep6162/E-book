docker compose stop db
docker compose rm -f db
docker volume inspect orders_lab_pgdata
docker compose up -d --wait db
docker compose exec -T db psql -U orders_admin -d orders \
  -v ON_ERROR_STOP=1 -c "SELECT * FROM survival_test;"
