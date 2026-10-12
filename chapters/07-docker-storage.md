# Chapter 7: Containers Die; Data Must Survive: Understand Docker Storage

::: {.callout .failure}
## The Image Update That Deleted Orders

The engineer pulls a newer PostgreSQL image, removes the old container, and launches a replacement. Startup succeeds. The application connects successfully. Every customer order is gone.

PostgreSQL had written its data directory into the old container's writable layer. Removing that container deleted the only copy. The team mistook a running database process for protected data.
:::

Restarting a container ordinarily preserves its writable layer; deleting and replacing it does not. Distinguish those operations before writing a runbook. **Data survival must be demonstrated across replacement, not inferred from restart success.**


## Three Storage Lifecycles

The writable layer belongs to one container. It is convenient for disposable process state but unsuitable as the sole durable copy of a database. Image layers are read-only inputs; runtime database writes do not become part of the image.

A named volume is managed independently by Docker. Removing a container normally leaves the volume. A replacement container can mount the same volume, provided it runs on the same storage host or a deliberately configured volume driver.

A bind mount maps a specific host path into the container. It gives explicit control over placement, backup tools, and permissions, but makes host filesystem assumptions part of the deployment contract. An empty or wrong directory can mask the expected container path.

Neither named volumes nor bind mounts automatically protect against disk failure, host termination, malicious deletion, or application corruption. They solve a lifecycle boundary, not every recovery requirement.

| Storage | Survives container replacement | Survives host loss by itself | Typical use |
|---|---|---|---|
| Writable layer | No | No | Disposable cache or temporary state |
| Local named volume | Yes, if retained | No | Local database lab |
| Bind mount | Yes, if directory retained | No | Deliberately managed host storage |
| External durable service | Depends on service | Depends on architecture | Production state with independent recovery |

## Establish the Data Contract

This lab uses PostgreSQL 17 and its `/var/lib/postgresql/data` mount path. Later major image families can change their recommended volume layout; inspect the selected image documentation before upgrading. Pin a reviewed image digest through `POSTGRES_IMAGE`.

Create a password file locally, protect it, and keep it outside Git. The image reads it during initial database setup. Changing that file does not automatically rotate an existing database password.

```bash
mkdir -p secrets
chmod 700 secrets
umask 077
# Generate locally; do not print the secret into shared logs.
openssl rand -base64 32 > secrets/postgres-password
```

### docker-compose.yml

```yaml
services:
  db:
    image: ${POSTGRES_IMAGE:?Set a reviewed PostgreSQL 17 digest}
    restart: unless-stopped
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: orders_admin
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - orders_data:/var/lib/postgresql/data
    # No host port: only approved local containers need this database.
    healthcheck:
      test: [CMD-SHELL, "pg_isready -U orders_admin -d orders"]
      interval: 5s
      timeout: 3s
      retries: 10
    stop_grace_period: 60s
volumes:
  orders_data:
    # A stable name makes project-directory changes less surprising.
    name: orders_lab_pgdata
secrets:
  db_password:
    file: ./secrets/postgres-password
```

Compose secrets in this local configuration are mounted files, not an encrypted cloud secret-management system. Administrators with access to the file or Docker daemon can retrieve them. Do not represent this lab mechanism as production credential isolation.

The initialization user is powerful. A real application requires a separate least-privilege database role with only the permissions its transactions need. Keep schema migration privileges separate when possible. The lab administrator account simplifies the demonstration, not the production threat model.

## Permissions Must Match the Image

The official PostgreSQL image may start its entrypoint with elevated privilege to prepare the data directory and then switch identity. Hard-coding `user: 10001` from the API example can break initialization.

Inspect the selected image's documented identity and entrypoint behavior. For bind mounts, set ownership for that image and host policy; do not assume PostgreSQL always uses a universal numeric UID. Rootless Docker and user-namespace remapping add another translation layer.

Never solve a permission failure with `chmod -R 777`. That permits unrelated processes to modify database files and hides an incorrect ownership contract. Document the mount source, filesystem, required identity, and permitted backup identity.

## Prove Container Replacement Is Safe

Start the database after setting a real reviewed digest. Keep one Compose project directory and verify the volume attachment.

```bash
docker compose config --quiet
docker compose up -d --wait
docker compose exec -T db psql -U orders_admin -d orders \
  -v ON_ERROR_STOP=1 -c \
  "CREATE TABLE survival_test (id integer PRIMARY KEY, note text);"
docker compose exec -T db psql -U orders_admin -d orders \
  -v ON_ERROR_STOP=1 -c \
  "INSERT INTO survival_test VALUES (1, 'survives replacement');"
```

Now remove only the container. This is a controlled lab exercise using synthetic data; do not substitute a production database name.

```bash
docker compose stop db
docker compose rm -f db
docker volume inspect orders_lab_pgdata
docker compose up -d --wait db
docker compose exec -T db psql -U orders_admin -d orders \
  -v ON_ERROR_STOP=1 -c "SELECT * FROM survival_test;"
```

The row must remain. Record the volume mount before and after replacement. If a new empty database appears, inspect the actual mount and project naming before touching either volume; your old data may still exist under a different name.

::: {.callout .failure}
`docker compose down --volumes`, `docker volume rm`, and some cleanup workflows intentionally delete volume data. Routine application deployment must not include those operations. A broad pruning command can also remove unused volumes; an unmounted recovery volume is still valuable.
:::

## Backup Is an Application Operation

Copying a live PostgreSQL data directory with a filesystem tool is not a generally valid database backup. PostgreSQL has specific physical backup and write-ahead-log requirements. For this small lab, use a logical dump.

```bash
mkdir -p backups
chmod 700 backups
umask 077
docker compose exec -T db pg_dump \
  -U orders_admin -d orders -Fc \
  > backups/orders.dump
# Inspect the archive catalog; successful inspection is not a restore test.
docker compose exec -T db pg_restore --list \
  < backups/orders.dump
```

A custom-format dump supports structured restoration, but one database dump does not include every cluster-wide role or configuration. Capture required roles, extensions, settings, and encryption dependencies separately. Protect the dump as customer data, not as an innocuous build artifact.

Restore into a disposable database on the lab instance, not over the primary. Use a unique test name and verify row counts and representative application queries.

```bash
docker compose exec -T db createdb \
  -U orders_admin orders_restore_test
docker compose exec -T db pg_restore \
  -U orders_admin -d orders_restore_test \
  --exit-on-error --no-owner < backups/orders.dump
docker compose exec -T db psql \
  -U orders_admin -d orders_restore_test \
  -c "SELECT * FROM survival_test;"
```

A restore on the same host demonstrates dump usability, not disaster recovery. Copy encrypted backups to independently protected storage and rehearse restoration onto a replacement host with recovered credentials. Measure elapsed recovery and the newest recoverable transaction.

## Upgrades and Destruction Need Their Own Workflow

Do not attach PostgreSQL 17 data files to an arbitrary later major image and expect a safe upgrade. Major upgrades require a supported migration process such as `pg_upgrade`, logical migration, or managed-service procedures. Test extensions, collations, clients, and rollback boundaries.

Before upgrading, capture an application-consistent recovery point and prove it can restore. Prefer a tested rehearsal using a representative dataset. A successful container startup is insufficient: check migrations, query results, application writes, and background processing.

For cleanup, stop the lab containers first. Decide whether to retain the named volume and backup. If deletion is intentional, record exactly which volume will be removed and verify it does not belong to another project. Keep destructive cleanup separate from commands readers run to demonstrate replacement survival.

**Persistence is a property of the storage lifecycle; recoverability is a property of the entire tested recovery procedure.** The next chapter applies that distinction to Jenkins, where configuration, encrypted credentials, and history have different backup requirements from application orders.

## Detect an Empty Mount Before Writing

A database that unexpectedly initializes a fresh cluster may indicate a wrong mount rather than deleted data. Stop application writes, inspect the container's mount source, and compare it with the expected volume identity. Do not copy new files over the old volume until ownership is understood.

Record the initialized database identifier and schema revision in operational inventory. Startup checks can detect a missing expected schema and fail closed rather than accepting an empty database as healthy. Such checks must distinguish a deliberate new environment from an accidental replacement mount.

This protects against a common failure: the system looks available while silently accepting new orders into a different database. Recovery then becomes reconciliation of two write histories rather than restoration of one missing service.

::: {.callout .protip}
Prove data survives container replacement and a separate backup restoration.
:::

::: {.callout .takeaways}
- **Container restart and container replacement have different data consequences.**
- **Named volumes outlive containers, not necessarily hosts.**
- **Match mount paths and ownership to the selected image version.**
- **Do not copy live database files casually or use world-writable permissions.**
- **Prove both replacement survival and restoration from backup.**
- **Treat volume deletion and database upgrades as deliberate operations.**
:::

## References

- Docker volumes: [Documentation](https://docs.docker.com/engine/storage/volumes/)
- PostgreSQL backup: [Documentation](https://www.postgresql.org/docs/17/backup.html)
