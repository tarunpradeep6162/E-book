# Chapter 21: Failover Is a Data Problem: Engineer Disaster Recovery

::: {.callout .failure}
## DNS Moved; Writes Still Failed

The AWS application region becomes unavailable. Global DNS changes to Azure, and the API begins receiving traffic there. Its database is still a read-only standby. Order creation fails while monitoring reports that the recovery endpoint is reachable.

The team prepared traffic routing but never rehearsed data promotion. Worse, nobody can prove the old primary is unable to resume writing. **A recovery endpoint is not a recovered service until write ownership and data correctness are established.**
:::

## Architecture at a Glance

![Fence the old writer, approve the recovery point, promote, then route and verify.](images/21-failover.svg){width=100%}

Explore the five recovery states in the [interactive companion](https://github.com/tarunpradeep6162/E-book/blob/main/interactive/failover.html). Download the file and open it in a browser; it performs no cloud operations.



## Active-Passive Has One Writer

In active-passive architecture, one site owns writes and the secondary maintains a recoverable copy. Recovery requires choosing an acceptable recovery point, fencing the previous writer, promoting the secondary, and reconnecting clients.

Active-active requires conflict handling, globally meaningful identity, write routing, and data semantics that support concurrent ownership. Deploying the same API in two clouds against independent databases does not create an active-active order service.

For this runbook, use a deliberately configured self-managed PostgreSQL physical standby in Azure. The replication, TLS, WAL retention, storage, and monitoring must already have been tested. This is not a claim that an RDS instance can automatically become an Azure-managed read replica.

The example promotion command applies to self-managed PostgreSQL 17. Managed services require their own supported promotion APIs and documented replication compatibility. Do not substitute a managed database and reuse `pg_ctl` blindly.

## Measure RPO and RTO Before the Incident

RPO is the maximum accepted recovery gap. Replication lag must be observed before failure because the primary may become unreachable during the incident. Monitor replay progress and retained WAL, not just a green replication connection.

RTO includes detection, decision-making, fencing, promotion, application rollout, DNS behavior, and validation. A database promotion taking ten seconds does not prove a ten-second service recovery.

For the book's target, validate that the newest recovered committed order falls within five minutes and that the complete service returns within sixty minutes. If lag exceeds the accepted RPO, the incident commander must explicitly approve the data-loss decision or select another recovery path.

## Fence Before Promotion

Fencing prevents the former primary from accepting writes. Depending on the architecture, it can include shutting down verified primary compute, revoking a write lease, blocking the write path through independently controlled infrastructure, or another database-supported fencing mechanism.

DNS changes alone do not fence existing connections or internal workers. An unreachable primary is not necessarily stopped; it may still serve a subset of clients during a partition. Record positive evidence that the old writer cannot continue.

If your architecture cannot establish safe fencing during the planned failure, that is a design gap. Do not make simultaneous writes an undocumented emergency mode.

## Recovery Checklist

```markdown
# Active-Passive Recovery Record
Incident ID:
Commander and database owner:
Primary failure evidence:
Primary write-fencing evidence:
Newest observed replication checkpoint:
Accepted recovery gap and approver:
Secondary storage/identity/network verification:
Promotion start/end:
Application image and configuration revision:
DNS change identifier:
Synthetic order and worker result:
Service recovery timestamp:
Failback owner and restrictions:
```

Keep this record outside the failed site's control plane. It must remain available when the primary CI, identity session, or state backend cannot be reached.

## Inspect the Secondary

Use an explicitly named Azure recovery context with independently available credentials and private connectivity. This example assumes the PostgreSQL container includes the official image's `gosu` utility and the configured `PGDATA` directory.

```bash
export RECOVERY_CONTEXT=azure-recovery
kubectl --context "$RECOVERY_CONTEXT" -n data get pod postgres-0
kubectl --context "$RECOVERY_CONTEXT" -n data exec postgres-0 -- \
  psql -U orders_admin -d orders -v ON_ERROR_STOP=1 \
  -c "SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();"
```

Replay timestamps can be old on an idle database without implying active replication lag. Interpret them with source activity, LSN monitoring, and known synthetic checkpoints. Do not turn one timestamp into a universal RPO calculation.

Confirm the standby has required WAL and is consistent at the selected recovery point. Protect the diagnostic output; it may include infrastructure and transaction metadata. Verify available capacity, secret retrieval, image pulls, storage access, and application connection routing.

## Promote the Approved Standby

::: {.callout .failure}
Only after documented fencing and data-loss approval:
:::

```bash
kubectl --context "$RECOVERY_CONTEXT" -n data exec postgres-0 -- \
  gosu postgres pg_ctl \
  -D /var/lib/postgresql/data/pgdata promote -w -t 60

kubectl --context "$RECOVERY_CONTEXT" -n data exec postgres-0 -- \
  psql -U orders_admin -d orders -v ON_ERROR_STOP=1 \
  -c "SELECT pg_is_in_recovery();"
```

The final query must return false. Then execute a controlled write and verify it commits. Authentication success or TCP reachability alone is insufficient.

Promotion creates a new primary timeline. The old primary cannot simply resume and become its peer. Failback needs a deliberate re-seeding or supported reconciliation procedure, with source-of-truth ownership preserved.

If promotion fails, stop and inspect PostgreSQL logs and recovery status. Do not repeatedly run destructive recovery commands or create another independent primary without understanding the first attempt.

## Deploy the Recovery Application

The Azure cluster must use Azure storage and identity configuration, not the AWS EBS StorageClass from Chapter 15. Its application values should reference the newly writable endpoint and the same approved image digest.

```bash
# recovery/ contains complete reviewed Azure-specific manifests, not snippets.
kubectl --context "$RECOVERY_CONTEXT" apply --dry-run=server -f recovery/
kubectl --context "$RECOVERY_CONTEXT" apply -f recovery/
kubectl --context "$RECOVERY_CONTEXT" -n orders \
  rollout status deployment/orders-api --timeout=180s
```

The recovery directory is an environment implementation prerequisite. Populate it from the complete application manifests and tested Azure integrations; the commands do not create that architecture automatically.

Reconnect pools deliberately. Verify the API and worker use the promoted endpoint, correct TLS identity, and least-privilege credentials. Keep external side effects disabled until duplicate-processing and write-ownership checks pass.

## Update Independently Controlled DNS

Use a DNS control plane whose recovery access does not rely on the failed application region. The example uses a pre-existing Cloudflare CNAME record with known zone and record IDs. Adapt the operation to your actual authoritative provider; do not create duplicate records as an emergency shortcut.

```bash
# Set these from the protected recovery inventory; token never goes in Git.
export DNS_ZONE_ID=REPLACE_ZONE_ID
export DNS_RECORD_ID=REPLACE_RECORD_ID
export DNS_API_TOKEN=RETRIEVE_FROM_SECRET_SOURCE
umask 077
header_file=$(mktemp)
trap 'rm -f "$header_file"' EXIT
printf 'Authorization: Bearer %s\n' "$DNS_API_TOKEN" > "$header_file"
unset DNS_API_TOKEN
cat > dns-change.json <<'JSON'
{
  "type": "CNAME",
  "name": "orders.example.com",
  "content": "recovery.example.net",
  "ttl": 60,
  "proxied": false
}
JSON
curl --fail-with-body --silent --show-error \
  --request PATCH \
  --header "@$header_file" \
  --header 'Content-Type: application/json' \
  --data @dns-change.json \
  "https://api.cloudflare.com/client/v4/zones/$DNS_ZONE_ID/dns_records/$DNS_RECORD_ID"
```

Verify the API response indicates success. Replace names and ensure the record type matches the existing record. Proxied records have provider-specific TTL behavior; this example deliberately uses DNS-only routing.

Lowering TTL during an incident does not invalidate already cached records with older TTLs. Clients may cache beyond expectations, keep existing connections, or use different recursive resolvers. Measure real traffic convergence and maintain fencing throughout it.

## Verify Service, Then Declare Recovery

Create a synthetic order using the recovery endpoint and an idempotency key. Confirm the row exists, the worker completes expected processing, and the result appears through the public API. Reconcile acknowledged requests near the failure boundary with recovered records.

Check error rates, latency, backlog, database saturation, and external dependencies. A recovered service operating beyond safe capacity can fail again immediately. Use admission controls and communicate any reduced service envelope.

Record actual RPO and RTO with evidence. If customer data was lost, report the gap precisely. Do not redefine the objective after the incident to make the exercise pass.

## Failback Is Another Migration

Keep the former primary fenced. Rebuild it from the current authoritative data, establish replication, verify catch-up, and schedule an approved reverse cutover. Do not repoint DNS merely because AWS is healthy again.

Preserve incident logs and state snapshots. Terraform repairs infrastructure ownership; PostgreSQL recovery repairs data continuity. Neither should be used to hide the other's unresolved state.

Rehearse this process with synthetic data before relying on it. The successful deliverable is one writer, measured data continuity, and a functioning order workflow under the defined failure—not a dashboard showing two healthy clusters.

## Preserve the Recovery Decision

Record who authorized promotion, which recovery point was accepted, and how primary fencing was established. These facts are part of data governance and incident reconstruction, not optional paperwork after service returns.

Keep customer-facing reconciliation separate from technical promotion. Some requests near the failure boundary may have committed without the caller receiving a response. Use idempotency records and order evidence to avoid treating all timeouts as lost transactions.

After recovery, compare the accepted gap with actual recovered records and identify any missing acknowledgements or duplicate side effects. Assign a remediation owner and preserve the evidence before logs expire.

This closes the recovery loop: uptime returns first, but correctness, reconciliation, and an independently verified failback plan complete the incident.

Keep the reconciliation owner assigned until ambiguous requests and duplicate external effects have been investigated and resolved.

::: {.callout .protip}
Record positive fencing evidence before approving a second writer.
:::

::: {.callout .takeaways}
- **Failover requires write ownership, not just traffic routing.**
- **Fence the old primary before promoting a secondary.**
- **Measure recovery gaps from transaction evidence.**
- **Use promotion commands appropriate to the actual database implementation.**
- **DNS caching and existing connections complicate cutover.**
- **Treat failback as a controlled data migration.**
:::

## References

- PostgreSQL standby operation: [Documentation](https://www.postgresql.org/docs/17/warm-standby.html)
- Cloudflare DNS API: [Documentation](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/edit/)
