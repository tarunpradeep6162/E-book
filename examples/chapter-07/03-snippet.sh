docker compose config --quiet
docker compose up -d --wait
docker compose exec -T db psql -U orders_admin -d orders \
  -v ON_ERROR_STOP=1 -c \
  "CREATE TABLE survival_test (id integer PRIMARY KEY, note text);"
docker compose exec -T db psql -U orders_admin -d orders \
  -v ON_ERROR_STOP=1 -c \
  "INSERT INTO survival_test VALUES (1, 'survives replacement');"
