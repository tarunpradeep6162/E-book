# Chapter 16: Release Without Roulette: Deployments, Promotion, and Rollback

::: {.callout .failure}
## Green Pods, Unusable Service

The new release starts successfully, and its readiness endpoint returns 200 before configuration and database initialization finish. During a rolling update, Kubernetes considers the new replicas ready and removes old capacity. User requests fail even though the deployment reports progress.

A readiness endpoint pointing at a nonexistent path would normally block progress instead; the catastrophic case is a probe that incorrectly reports usable capacity. **Readiness must describe the serving contract, not merely the existence of a process.**
:::

## Architecture at a Glance

![Green serves while Blue is updated and verified; traffic switches only after the release gate.](images/16-blue-green.svg){width=100%}



## Package Configuration Without Rebuilding

Helm templates package Kubernetes configuration. Values select environment behavior, but the application image remains the same tested digest. Keep chart version, image digest, configuration revision, and schema compatibility in the release record.

Do not rebuild an image for each environment. If production needs a different endpoint, configure it at runtime. Rebuilding creates a new artifact that did not pass the same staging evidence.

Charts need explicit contracts. A values schema can reject missing image digests, invalid replica counts, or unsupported configuration shapes before deployment. Template checks do not prove live admission compatibility, sufficient capacity, or application correctness.

## Environment Values

### values-dev.yaml

```yaml
image:
  repository: registry.example/orders-api
  digest: sha256:REPLACE_REVIEWED_DIGEST
replicaCount: 1
resources:
  requests: {cpu: 100m, memory: 64Mi}
  limits: {cpu: 500m, memory: 128Mi}
rollout:
  maxSurge: 1
  maxUnavailable: 0
config:
  logLevel: debug
```

### values-prod.yaml

```yaml
image:
  repository: registry.example/orders-api
  digest: sha256:REPLACE_SAME_REVIEWED_DIGEST
replicaCount: 3
resources:
  requests: {cpu: 250m, memory: 256Mi}
  limits: {cpu: 1000m, memory: 512Mi}
rollout:
  maxSurge: 1
  maxUnavailable: 0
config:
  logLevel: info
```

The production values are capacity hypotheses, not benchmark results. Debug logging should not expose secrets even in development. Secrets must remain references to protected sources rather than plaintext values in Git or Helm release history.

### templates/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  progressDeadlineSeconds: 180
  minReadySeconds: 10
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: {{ .Values.rollout.maxSurge }}
      maxUnavailable: {{ .Values.rollout.maxUnavailable }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: api
          image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
          ports:
            - name: http
              containerPort: 8080
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 10
```

This template excerpt must be combined with the security context, service account, temporary volume, and startup behavior from Chapter 12 before deployment. The repository labels partial templates explicitly; do not apply this excerpt as if it were the entire secure chart.

## Rolling Updates Need Headroom

`maxUnavailable: 0` keeps requested old serving capacity while replacements become ready. `maxSurge: 1` permits one extra Pod. Neither guarantees zero downtime: readiness accuracy, endpoint propagation, connection draining, topology, and actual capacity still matter.

A surge Pod that cannot schedule can stall the release. A cluster autoscaler may add capacity, but node startup and image retrieval take time. Reserve or prove sufficient headroom and define a deployment timeout based on measured behavior.

`minReadySeconds` requires a period of stable readiness before treating a replica as available. It catches selected startup instability, not every business regression. Post-deployment checks must exercise order creation and processing.

## Choose a Traffic Strategy

Rolling updates replace replicas incrementally using the ordinary Service. They are simple but temporarily mix versions, requiring API and schema compatibility.

Blue-green releases maintain two versions and switch traffic deliberately. They need additional capacity and still require safe database coexistence. Switching a Service selector does not drain every existing connection instantly or update every external load balancer at the same moment.

Canary releases expose a small share of real traffic to the candidate and compare behavior. Kubernetes replica ratios alone do not guarantee exact traffic percentages. Use a reviewed ingress, gateway, or rollout controller capable of the intended traffic weighting.

The canary gate should compare error rates, latency, business transactions, and relevant downstream pressure. A healthy candidate serving only simple read requests may still fail order writes. Define the request mix and sample size before concluding it is safe.

## Release Gates

Before promotion, verify trusted image evidence, signature policy where configured, configuration validity, migration compatibility, spare capacity, and recovery readiness. The approver must know what is changing and how the old version can still run.

```bash
helm lint ./charts/orders-api
helm template orders-api ./charts/orders-api \
  -f values-prod.yaml > rendered.yaml
# Validate in the intended existing namespace and context.
kubectl apply --dry-run=server -f rendered.yaml
helm upgrade --install orders-api ./charts/orders-api \
  --namespace orders -f values-prod.yaml \
  --wait --timeout 5m --atomic
```

The full chart must exist and placeholders must be replaced. These commands demonstrate the release workflow, not an invitation to bypass chart completeness checks.

Helm `--atomic` attempts rollback when an upgrade fails according to Helm's checks. It cannot reverse external side effects, every hook action, or committed database migrations. Readiness failure detection and rollback policy remain application-aware decisions.

## Rollback Has a Compatibility Boundary

An image rollback can restore application code. It cannot recover deleted rows or restore a dropped database column. If the new application wrote incompatible records, the old code may fail after an apparently successful rollback.

Use additive schema changes and a compatibility window. Execute destructive migrations only after older consumers are retired and the recovery decision is explicit. A migration backup is valuable only when restoration and subsequent write loss are understood.

Record Helm history and the image/configuration identities of each revision. Do not assume a chart rollback recreates secret values that changed outside Helm. Runtime secret rotation and external feature flags need their own historical record and recovery procedures.

## Verify User Behavior

After rollout, test through the actual user entry point rather than only port forwarding into a Pod. Create a synthetic order with an idempotency key, observe worker processing, and verify expected data persistence. Use a dedicated synthetic identity and avoid polluting real billing or fulfillment systems.

Compare metrics before, during, and after release. Distinguish startup noise from sustained regression, and define the observation window. A pipeline that finishes immediately after readiness may miss failures triggered by scheduled jobs or connection-pool saturation.

Exercise a failing image pull, insufficient capacity, false readiness, and an incompatible migration in staging. Confirm the release halts, alerts identify the right cause, and rollback or forward repair follows the documented compatibility boundary.

## State and Authority

Helm release records live in the cluster and can contain rendered values. Restrict their access and avoid storing secrets unnecessarily. Git stores chart definitions and non-secret values; the registry stores immutable images; the database owns durable records.

Give the deployment identity only the required namespace-scoped permissions where possible. Cluster-wide custom resources or admission components need separately reviewed authority. A chart that installs cluster administration should not run under an ordinary application release role.

Destroying the namespace is not a release rollback. It can remove secrets, claims, and release records. Keep destructive cleanup separate from version promotion and incident repair.

## A Release Needs a Decision Window

Define how long to observe the candidate and what evidence causes promotion, rollback, or a pause. Some failures occur only after caches expire, scheduled workers run, or connection pools reach steady state. A thirty-second smoke test may miss all three.

Use a release checklist that names the old and new image digests, configuration revision, migration revision, expected traffic mix, and the compatible rollback target. Keep the observation period bounded so an ambiguous canary does not become a permanent mixed-version state.

Compare candidate and baseline under similar traffic. If the canary receives a different customer segment or only cached requests, lower latency may reflect the request mix rather than better behavior. Preserve trace context and bounded labels to analyze the difference without leaking customer data.

For blue-green switching, identify sessions and background workers that remain on the old version. Traffic routing to a new frontend does not stop an old worker from writing. Disable or retire competing consumers only through a workflow that preserves in-flight work and idempotency.

A rollback gate should consider data compatibility before automation acts. Automatically reverting code after a destructive migration can make the outage worse. Where compatibility is uncertain, pause traffic or apply an approved forward fix rather than guessing.

Record the final decision and its supporting evidence in the release inventory. If the release is paused, specify who owns it and which version currently serves each path. Operational ambiguity itself is a risk during the next incident.

This discipline makes deployment a controlled change in service behavior, rather than a sequence of Kubernetes objects that happened to reconcile.

Record observation-window results before promotion, including whether background workers completed successfully under the candidate configuration and schema.

::: {.callout .protip}
Preserve schema compatibility while old and new application versions coexist.
:::

::: {.callout .takeaways}
- **Promote the same image digest with reviewed environment configuration.**
- **Readiness must reflect usable serving capacity.**
- **Rolling updates need spare capacity and graceful termination.**
- **Canary weighting requires an actual traffic-control mechanism.**
- **Application rollback does not reverse database side effects.**
- **Verify complete order workflows through the real entry point.**
:::

## References

- Helm upgrade: [Documentation](https://helm.sh/docs/helm/helm_upgrade/)
- Deployment strategies: [Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
