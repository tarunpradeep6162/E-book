# Chapter 17: Scale What You Can Measure: Reliability and Observability

::: {.callout .failure}
## Fifty Replicas, One Exhausted Database

The API becomes CPU-bound during a promotion. HPA adds replicas, each opening a large PostgreSQL connection pool. The database reaches its connection limit, queries queue, and every new Pod increases the pressure.

The autoscaler followed its CPU signal. The architecture failed to bound downstream demand. **Scaling the caller is not the same as increasing end-to-end capacity.** Observe the bottleneck before deciding which component should grow.
:::

## Define the Service's Evidence

Metrics summarize rates, distributions, and resource use. Logs explain individual events and errors. Traces connect work across services. None is a complete substitute for the others.

For the order API, measure request rate, errors, latency distribution, active requests, database pool occupancy, query latency, and timeout rates. For the worker, measure queue age, pending work, processing duration, retries, and dead-letter or failed-work counts.

Business completion matters: accepting an order while the worker never processes it is not a healthy order service. Define an objective for completion latency and durability separately from HTTP availability.

Protect telemetry as operational data. Logs can contain customer identifiers, tokens, SQL parameters, and exception details. Redact deliberately, restrict readers, and establish retention. Do not log authorization headers to simplify debugging.

## Capacity Is a Budget Across Dependencies

Suppose the database allows 200 application connections after reserving administrative and recovery capacity. If each API replica can open ten connections, twenty replicas already consume that budget before workers are counted.

Choose a maximum replica count together with pool limits, worker concurrency, query behavior, and proxy or pooling architecture. Database CPU, I/O, locks, and memory can become bottlenecks before the connection ceiling is reached.

Retries also consume capacity. Use bounded exponential backoff with jitter and idempotency. A timeout does not prove the transaction failed; retrying blindly can duplicate work. Admission control and load shedding may protect the database better than adding more callers.

## HPA Requires Requests and Metrics

CPU utilization percentages are relative to CPU requests. Missing requests or unavailable metrics can prevent the intended scaling behavior. The cluster needs a supported metrics pipeline and sufficient node capacity.

### hpa.yaml

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: orders-api
  namespace: orders
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: orders-api
  minReplicas: 3
  maxReplicas: 10 # Chosen with the database connection budget.
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 65
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 20
          periodSeconds: 60
```

These values are a controlled starting point, not a universal tuning answer. Measure how quickly a new replica becomes useful and whether scale-up increases database pressure. A slow image pull or startup path can make aggressive scaling ineffective.

The Deployment still needs its CPU requests. When HPA owns replica count, do not repeatedly apply a static replica value that fights it. Helm and GitOps ownership must account for that field.

CPU is not always the right signal. A worker waiting on I/O can accumulate backlog while using little CPU. Queue age or pending work may require a custom or external metrics adapter. Validate adapter failure behavior and metric semantics before making them release gates.

## PDBs Protect Selected Maintenance

A PodDisruptionBudget constrains voluntary disruptions using the eviction API. It does not guarantee survival during node crashes, network partitions, or every rollout mechanism.

### pdb.yaml

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: orders-api
  namespace: orders
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: orders-api
```

With three healthy replicas, this permits selected maintenance while retaining two. If readiness falls or capacity is absent, drains can block. Do not remove the PDB automatically to make an upgrade finish; investigate why the availability requirement cannot be met.

PDBs and Deployment rollout settings control different operations. Match them with topology-spread rules, surge capacity, and node-group maintenance behavior. A strict budget on a single replica can block maintenance without providing real redundancy.

## Alerts Need Actionable Semantics

Alert on customer impact and imminent exhaustion rather than every harmless spike. Example conditions include sustained error rate above the SLO threshold, oldest pending order exceeding its completion objective, database pool saturation, and unavailable ready capacity.

Define each alert's owner, severity, evidence, and first diagnostic steps. Include service identity and environment without embedding secrets. Test the actual notification route; an alert rule that fires only in a dashboard nobody watches is incomplete.

Use latency histograms with appropriate buckets rather than averaging durations. An acceptable mean can hide a severe tail. Choose bucket boundaries around the service objective and inspect aggregation across replicas carefully.

High-cardinality labels such as order IDs can overwhelm the metrics system. Put per-order context in logs or traces and use bounded labels for metrics. Telemetry ingestion must have its own resource and retention budgets.

## Controlled Load Testing

Use an isolated environment and synthetic requests. Define the request mix, arrival model, payload distribution, data size, and duration. A loop of cached health requests does not benchmark order processing.

Observe baseline, gradual increase, peak, sustained load, and recovery. Record throughput alongside errors and latency; a system serving fewer requests can appear faster while failing the workload.

```bash
kubectl -n orders get hpa
kubectl -n orders describe hpa orders-api
kubectl top pods -n orders
kubectl -n orders get pdb
kubectl -n orders get pods -o wide
```

These commands require working metrics and appropriate permissions. Inspect HPA conditions when desired replicas do not change. Separate metric unavailability, replica limits, insufficient node capacity, and readiness failures.

During the test, compare database connections with the predicted maximum. Verify worker concurrency and retry traffic remain bounded. Observe scale-down: killing idle-looking replicas can still interrupt long requests or claimed work if termination handling is wrong.

## Recovery and Telemetry State

Version dashboards, alert rules, collectors, and retention configuration. Time-series data and logs need explicit storage ownership; they do not automatically survive collector or cluster replacement.

Keep an independent incident path when the primary monitoring stack fails. Cloud service events, external probes, and protected operational access can help distinguish application failure from observability failure. Do not make every alert delivery depend on the same cluster being monitored.

Back up configuration and test recovery of the minimum diagnostic capability. Recovery objectives for telemetry can differ from order data, but losing all evidence during an incident may significantly increase service RTO.

## Tune with Evidence

Change one important scaling parameter at a time and compare equivalent tests. Record why the maximum replica count, pool size, and stabilization windows were chosen. Preserve before-and-after evidence in the architecture decision record.

A larger node or managed database tier may help, but first identify locks, inefficient queries, unbounded pools, and retry amplification. Capacity purchases without diagnosis can merely move the failure threshold.

The successful result is a measured envelope: within a defined request rate and data profile, the service meets its latency and completion objectives; beyond it, the system degrades predictably without losing committed orders.

## Protect the Database During Scale-Up

A connection pool should have bounded size, acquisition timeout, and clear behavior when exhausted. Avoid allowing every waiting request to open another connection. Expose pool occupancy and wait duration so operators can see whether the bottleneck is connection admission or query execution.

Apply similar bounds to the worker. Increase concurrency only when database and external side-effect capacity support it. Queue depth alone is not permission to launch unlimited processing. Long-running transactions and locked rows can keep CPU low while progress stops.

Measure retry amplification as its own signal. If one customer request produces several database attempts, apparent workload can rise faster than incoming traffic. Use time budgets across the request path so nested retries do not exceed the original service deadline.

HPA scaling needs a stable relationship between the metric and useful capacity. Observe whether adding a replica actually reduces per-replica pressure without increasing total failures. If not, the chosen signal or bottleneck model is wrong.

Separate resource exhaustion from correctness failures. A fast API returning incorrect order status is not successful capacity. Synthetic checks should validate durable state and worker completion alongside latency.

After the load ends, verify backlog drains within the expected window and scaling returns to its minimum without stranding work. Watch memory behavior and connection release across repeated cycles; a single short test can hide gradual leaks.

Preserve the dataset size, index state, and query mix used in the benchmark. Performance results from an empty database do not support a mature production workload. Capacity decisions should cite the actual test envelope and known limits rather than one impressive throughput number.

Use the measured safe envelope to set admission limits before traffic exceeds it, rather than waiting for database exhaustion.

::: {.callout .protip}
Bound replica count and connection pools against measured database capacity.
:::

::: {.callout .takeaways}
- **Observe the complete transaction path before scaling callers.**
- **Bound replicas and connection pools together.**
- **HPA needs meaningful requests, metrics, and capacity.**
- **PDBs constrain voluntary disruption, not every failure.**
- **Alert on actionable impact and test notification delivery.**
- **Record a measured capacity envelope and recovery behavior.**
:::

## References

- HPA: [Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- Disruption budgets: [Documentation](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
