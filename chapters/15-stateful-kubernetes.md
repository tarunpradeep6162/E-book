# Chapter 15: Stateful Kubernetes: Storage, Databases, and Safe Migrations

::: {.callout .failure}
## The Database Could Not Follow the Pod

A node in AZ A fails. The database replacement is expected to run in AZ B, but its existing EBS volume belongs to AZ A. The scheduler reports a volume topology conflict, and the database remains unavailable.

Kubernetes does not normally solve that conflict by moving an EBS volume across zones. EBS is zonal; changing Pod placement does not change that storage boundary. The outage came from assuming process replacement implied data mobility.
:::

**Schedule state with its storage constraints, and recover data through a tested replication or restore procedure.** Availability Zones are not interchangeable mount points.


## Architecture at a Glance

![An existing EBS volume stays in its zone. Cross-zone recovery creates or uses a different data copy.](images/15-storage-topology.svg){width=100%}



## PV, PVC, and StorageClass Have Different Owners

A PersistentVolume represents storage capacity available to the cluster. A PersistentVolumeClaim requests capacity with access and class requirements. A StorageClass describes how dynamic provisioning should obtain that capacity.

The CSI driver connects Kubernetes storage operations to the underlying cloud service. Installing its manifests without the required identity, permissions, compatible version, and node components does not establish a working storage platform.

For EBS, use a supported EBS CSI driver with a narrowly scoped cloud identity. Record which deployment system owns the driver and its version. The following lab assumes it is already installed and functioning; the database manifest does not install it.

`ReadWriteOnce` means a volume can be mounted read-write by a single node in the relevant semantics, not that it is a universal one-Pod security boundary. `ReadWriteOncePod` provides different behavior with compatible drivers. Understand the selected access mode before attempting failover.

## Provision with Scheduling Context

`WaitForFirstConsumer` delays provisioning until scheduling requirements are known. That helps avoid creating a volume in a zone incompatible with the eventual Pod. It does not make an existing zonal volume portable across zones.

### First, Read the Smallest Contract

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: orders-ebs-gp3
provisioner: ebs.csi.aws.com
```

This identifies the storage provisioner. The complete class below adds topology-aware binding, encryption, expansion, and retention policy.

### storage-class.yaml

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: orders-ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Retain # Claim deletion must not automatically erase data.
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

For customer-managed encryption, supply the approved KMS configuration supported by the driver and verify its IAM/key-policy requirements. Encryption flags do not guarantee the recovery role can decrypt a restored volume.

A Retain policy preserves the storage object after claim deletion, but administrators can still delete cloud volumes. Retained resources require ownership inventory and cleanup procedures; otherwise the result is both a recovery hazard and a recurring storage bill.

## A Single-Instance Database Lab

This PostgreSQL StatefulSet demonstrates stable identity and persistent claims. It does not provide database replication, automatic primary election, or cross-AZ database availability. Do not increase `replicas` and expect three independent PostgreSQL containers to become one replicated database.

Create a protected `postgres-auth` Secret containing `password` through your approved secret workflow. Avoid putting literal credentials in the manifest or shell history. The image reference must point to the reviewed PostgreSQL 17 digest.

### postgres.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: data
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - name: postgres
      port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: data
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      terminationGracePeriodSeconds: 60
      containers:
        - name: postgres
          image: postgres:17@sha256:REPLACE_DIGEST
          ports:
            - name: postgres
              containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: orders
            - name: POSTGRES_USER
              value: orders_admin
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-auth
                  key: password
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              memory: 1Gi
          readinessProbe:
            exec:
              command: [pg_isready, -U, orders_admin, -d, orders]
            periodSeconds: 5
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: orders-ebs-gp3
        resources:
          requests:
            storage: 20Gi
```

The official image's entrypoint can need elevated permissions to initialize storage before switching to its database user. This lab manifest does not claim compliance with a namespace's restricted Pod Security policy. Review the chosen image and ownership initialization before enforcing non-root settings; do not copy the API's UID blindly.

The readiness command checks whether PostgreSQL accepts connections. It does not prove application credentials, schema compatibility, or transaction correctness. The admin initialization user is not the role your API should use.

## Verify Claim and Zone

```bash
kubectl -n data get statefulsets,pods,pvc
kubectl get pv
kubectl -n data describe pod postgres-0
kubectl -n data describe pvc data-postgres-0
```

Inspect the PV's node affinity, the node's zone labels, and the underlying EBS volume. Create a synthetic row, replace the Pod, and verify persistence. Then simulate loss of the node in a lab with compatible replacement capacity in the same zone.

::: {.callout .failure}
A forced detach while the old writer is alive can risk data corruption. Confirm fencing and instance state before authorizing storage takeover. “The node is unreachable” is not proof that its database process cannot write.
:::

## Managed Services Are a Tradeoff

RDS removes many operational tasks associated with hosting PostgreSQL on Kubernetes, but does not remove schema design, credentials, connection management, backup policy, or application migration responsibilities.

Compare the real requirements: supported extensions, patch control, failover behavior, recovery objectives, staffing, cost, and compliance. In-cluster databases need operators or explicit procedures for replication, primary selection, backups, and upgrades. A StatefulSet alone supplies none of those database protocols.

Managed endpoints introduce DNS and connection-pool behavior during failover. Clients must reconnect correctly, respect TLS validation, and retry only safe operations. The application cannot assume a persistent TCP connection survives primary replacement.

## Migrate Schemas Safely

Use an expand-and-contract sequence. Add compatible structures, deploy consumers capable of working with both versions, backfill with monitored batches, then remove old structures in a later approved release.

A migration job must be serialized and identifiable. Multiple application replicas running startup migrations can contend or execute destructive operations unexpectedly. Give the migration identity only the required schema privileges and revoke unused elevated access.

Capture migration revision, image digest, database version, start/end timestamps, and validation results. A migration that commits successfully can still violate application expectations. Test representative queries and background processing before declaring success.

Rollback must account for data written under the new schema. Reverting the application image does not recreate dropped columns or translate new records automatically. Define a forward-fix or recovery decision before approving destructive changes.

## Backup and Recovery

Use PostgreSQL-aware backups and retained WAL where point-in-time recovery is required. Volume snapshots need a reviewed application-consistency mechanism; filesystem capture alone is not a complete database recovery contract.

Restore to isolated storage and validate database startup, schema revision, row counts, roles, and representative order workflows. Record the latest recoverable transaction to measure RPO. Include secret retrieval, KMS access, image retrieval, and network policy in the RTO measurement.

Cross-AZ recovery creates a new volume from a snapshot in the destination zone or uses database replication designed for that boundary. Update the storage ownership carefully; do not edit PV topology to pretend an old EBS volume moved.

## Cleanup and Ownership

Before deleting a StatefulSet or namespace, inspect PVC retention settings, PV reclaim policy, external snapshots, and recovery records. Keep names and volume IDs in the asset inventory. Never let a generic application cleanup job delete database storage.

Choose one owner for CSI installation and cloud identities. Terraform, Helm, and manually installed add-ons must not reconcile the same driver simultaneously. Recovery procedures should specify which layer is repaired first.

The lab is complete when Pod replacement preserves data and a separate restore exercise meets its measured target. Cross-AZ database availability remains unverified until a real replication or recovery architecture is tested.

## Storage Expansion Is an Operational Change

Increasing a PVC's requested size requires driver and StorageClass support. The cloud volume and mounted filesystem may complete expansion at different times, so monitor claim conditions and actual available capacity. Do not replace a database volume merely to enlarge it.

Before expansion, record the claim, PV, cloud volume, zone, encryption key, and backup checkpoint. Confirm the request changes the intended resource rather than creating a new empty claim with a similar name. Review whether the filesystem or database requires additional handling.

Database capacity planning includes IOPS, throughput, WAL growth, temporary files, and retained recovery data, not just table size. A volume with spare gigabytes can still be saturated by I/O. Observe service latency and queueing during growth.

Storage ownership must survive namespace or controller changes. If a migration creates a new claim, document which one becomes authoritative and how the old copy is retained or retired. Two writable database copies cannot be treated as harmless backup variants.

The acceptance result should include the expanded mounted capacity, unchanged representative records, and a successful recovery-point verification. This makes storage maintenance part of the same data-preservation discipline as release and failover.

Check retained cloud volumes after cleanup and assign an owner, so recovery data does not become an unidentified storage resource.

::: {.callout .protip}
Treat volume topology, database promotion, and schema recovery as separate mechanisms.
:::

::: {.callout .takeaways}
- **Zonal storage does not follow arbitrary Pod placement.**
- **WaitForFirstConsumer improves provisioning placement, not volume mobility.**
- **A StatefulSet supplies identity and claims, not database replication.**
- **Retain policies and encryption require recovery ownership.**
- **Schema migration and application rollback are different operations.**
- **Validate restoration with application transactions, not just Pod status.**
:::

## References

- StatefulSets: [Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- EBS CSI: [Documentation](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
