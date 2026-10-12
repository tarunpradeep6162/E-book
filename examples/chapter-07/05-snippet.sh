mkdir -p backups
chmod 700 backups
umask 077
docker compose exec -T db pg_dump \
  -U orders_admin -d orders -Fc \
  > backups/orders.dump
# Inspect the archive catalog; successful inspection is not a restore test.
docker compose exec -T db pg_restore --list \
  < backups/orders.dump
