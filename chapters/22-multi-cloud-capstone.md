# Chapter 22: Break It Before Production: The Multi-Cloud Capstone

::: {.callout .failure}
## Green Dashboards, Missing Packets

Launch day begins with healthy Pods and a successful deployment. Half the application's requests time out because an intermittent network path drops packets. The health endpoint uses a different path, and the monitoring dashboard stays green.

Staging had tested only successful startup. Nobody had interrupted a dependency, replaced a node under load, or verified that customer-impact alerts reached an operator.
:::

**Operational readiness requires observed behavior under defined failures.** A platform is credible when another engineer can provision, diagnose, recover, and retire it using documented procedures and approved identities.


## State the Experiment Before Creating the Fault

A game day begins with a hypothesis, scope, synthetic workload, expected observations, abort conditions, and rollback steps. The purpose is to learn whether a specific architectural claim holds—not to create random damage and hope monitoring explains it.

Use a dedicated lab account and disposable cluster. Exclude production customer data, real fulfillment actions, and production credentials. Confirm resource names and contexts before every fault command.

An experiment must have an independent stop mechanism. If the same network you are breaking carries your only administrative access, you have not designed a controlled exercise. Assign a fault operator, observer, incident commander, and recovery owner; one person can fill multiple roles only if the workload remains manageable.

## The Game Day Record

```markdown
# Experiment Record
Experiment ID and owner:
Approved account, cluster context, namespace:
Hypothesis:
Synthetic request mix and duration:
Fault and exact target:
Expected service behavior:
Expected metric/log/trace evidence:
Expected alert route and delivery deadline:
Abort conditions:
Independent stop mechanism:
Recovery commands and owner:
Start, detection, alert, recovery timestamps:
Observed RPO/RTO and data checks:
Unexpected behavior and follow-up owner:
```

Store evidence under restricted access and sanitize it before attaching to public book issues. Logs and packet captures can disclose addresses, tokens, and customer-like identifiers even in a test environment.

## Experiment One: Lose a Worker Node

Use a disposable multi-node kind cluster with a known worker container. List actual container names and explicitly select a worker; do not target the control-plane container or another project's node.

```bash
kubectl config current-context
docker ps --format '{{.Names}}'
export LAB_WORKER=REPLACE_OBSERVED_KIND_WORKER
# After verifying that this is the approved disposable worker:
docker stop "$LAB_WORKER"
kubectl get nodes
kubectl -n orders get pods -o wide
# Independent rollback:
docker start "$LAB_WORKER"
```

Stopping the node container approximates abrupt node unavailability. It is different from draining, which uses voluntary eviction behavior. Compare both experiments because PDBs do not govern every involuntary failure.

Observe detection latency, endpoint removal, replacement scheduling, image pulls, and service impact. If all replicas were on the failed node, the experiment should reveal the placement error. If spare capacity is absent, replacement may remain Pending even though the controller requests it correctly.

Check committed orders and worker idempotency after recovery. A node failure can interrupt an operation after its side effect but before acknowledgement. The application must handle retries without silently duplicating fulfillment.

## Experiment Two: Block the Database Dependency

Create a dedicated `gameday` namespace containing a reviewed clone of the application and synthetic database. Verify no existing additive allow policy defeats the intended experiment. The following policy isolates API egress and permits only the configured cluster DNS path; database TCP traffic is denied by omission.

### deny-database-egress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: experiment-deny-database
  namespace: gameday
spec:
  podSelector:
    matchLabels:
      app: orders-api
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
```

Verify your DNS implementation and enforcement first. The policy blocks other non-DNS egress too; in this isolated fixture the database must be its only application dependency. If testing a production-like dependency set, preserve explicit permissions for unrelated services instead of attributing every failure to PostgreSQL.

```bash
kubectl apply --dry-run=server -f deny-database-egress.yaml
kubectl apply -f deny-database-egress.yaml
kubectl -n gameday logs deployment/orders-api --tail=100
# Roll back only this experiment's policy.
kubectl -n gameday delete networkpolicy experiment-deny-database
```

An existing egress allow policy can permit traffic because policies are additive. Confirm the denied request and an approved control request before declaring the fault successful. Observe whether bounded timeouts, backoff, and admission behavior protect the database and clients.

Chaos Mesh or another reviewed fault controller can model delay and packet loss more precisely. Install it only in an authorized lab with pinned versions and documented privileges. Its custom-resource schemas and selectors must be validated against the installed release; do not paste unverified CRDs into production.

## Experiment Three: Lose Jenkins

Stop the lab controller through its service manager and measure how existing workloads behave. The expected result is interrupted build/release capability with existing applications still serving.

```bash
# Execute on the approved lab controller host, not production.
sudo systemctl stop jenkins-container
# Restore the service only after the persistent mount is verified.
findmnt /srv/jenkins
sudo systemctl start jenkins-container
```

Verify jobs, configuration, and credentials survive. Then rehearse controller replacement from backup on isolated compute. Confirm no production job fires automatically during recovery testing. Disable or redirect deployment credentials until the recovery controller is trusted.

A pipeline retry must not repeat destructive infrastructure changes or duplicate release publication. Review build IDs, approved plan identity, and registry immutability before resuming interrupted work.

## Experiment Four: Make State Unavailable

::: {.callout .failure}
Do not delete a production state bucket to demonstrate resilience. In a dedicated backend lab, temporarily remove the test writer's access or introduce a controlled backend outage and verify plans/applies fail closed.
:::

The expected result is existing workloads continue running while infrastructure changes stop. An agent must not fall back to local state and begin managing the same infrastructure as a fresh root.

Exercise a versioned-state restoration in the lab using Chapter 3's runbook. Deleting a whole bucket destroys a different boundary from deleting a current object version; choose the experiment deliberately and preserve independently protected recovery evidence.

Record how the team locates the correct backend, recovers credentials, verifies lineage and serial, and reconciles actual resources. A restored JSON file with unexpected delete proposals is not a successful state recovery.

## Verify Alerts Actually Arrive

For each fault, define the expected alert and inspect delivery to the configured receiver. Record detection time, delivery time, acknowledgement, and diagnostic usefulness. A dashboard condition changing color does not demonstrate on-call notification.

Use external synthetic probes for the user path and internal metrics for diagnosis. A collector on the failed node can disappear with its target; independent observations help distinguish telemetry failure from service recovery.

Validate that alert labels identify the correct environment and experiment. Suppress noise only through reviewed temporary routing, not by disabling the entire alert system. Remove experiment suppression afterward and prove normal routing resumes.

## Recovery and Data Verification

After each experiment, verify representative order creation, worker completion, stored records, and image/configuration identities. Compare observed outcomes with the architecture's stated RPO and RTO.

Test backups through restoration, not listing files. Check that recovery roles can decrypt retained data and retrieve images without primary-site services. Verify one writer after failover and keep the former primary fenced until failback is approved.

Measure the full recovery path, including human decisions and failed attempts. If the runbook requires knowledge absent from the repository, record and fix that gap before the next exercise.

## Readiness Is a Reviewable Result

The capstone deliverable contains all infrastructure roots, workload definitions, image evidence, dependency maps, threat models, release procedures, recovery records, and game-day findings. Static examples are not automatically a deployed platform; distinguish code completeness from operational verification.

Classify findings by consequence and owner. Block release on unresolved data-loss, privileged-access, or unbounded failure-amplification problems. Other limitations may be accepted with explicit scope and deadline; hiding them behind “all tests passed” prevents informed operation.

Finish with a teardown rehearsal. Identify retained storage, snapshots, keys, registries, public addresses, gateways, and log retention. Destroy disposable resources through their owners and verify remaining charges are deliberate.

The platform's final claim should be specific: under the tested topology, load, and failure conditions, service and recovery objectives were met with recorded evidence. Anything broader requires another experiment.

## Close Every Experiment

Remove only the experiment's fault objects and verify ordinary policy remains intact. Check for stopped lab nodes, temporary access rules, abandoned snapshots, altered routing, and muted alerts. Cleanup is a measured part of the exercise, not an assumption.

Assign each unexpected result an owner, severity, and verification test. Repeat the relevant experiment after the fix. A finding closed by changing a document alone does not demonstrate improved system behavior.

Keep the final readiness decision linked to those results so the next operator understands both tested guarantees and unresolved limits.

::: {.callout .protip}
Give every experiment an independent stop mechanism and prove ordinary controls return afterward.
:::

::: {.callout .takeaways}
- **Define a hypothesis, target, abort condition, and rollback before injecting failure.**
- **Use dedicated lab environments and synthetic data.**
- **Test abrupt failures separately from voluntary maintenance.**
- **Prove alert delivery and data correctness, not just recovery of processes.**
- **Keep CI and state outages from stopping existing workloads.**
- **Publish operational evidence and unresolved limitations honestly.**
:::

## References

- kind: [Documentation](https://kind.sigs.k8s.io/docs/user/quick-start/)
- Chaos Mesh: [Documentation](https://chaos-mesh.org/docs/)
