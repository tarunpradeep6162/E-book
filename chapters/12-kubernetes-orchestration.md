# Chapter 12: Kubernetes Beyond "It Runs": Orchestrate the Application

::: {.callout .failure}
## The Pods That Never Came Back

The team deploys three standalone Pods and calls the application highly available. A node fails, and the Pods assigned to it stop serving. There is no Deployment to create replacements on healthy capacity.

A container restart policy can restart a process within a surviving Pod environment; it does not give a standalone Pod a replacement controller after node loss. The team confuses process recovery with workload reconciliation.
:::

**Declare the workload you want maintained, not just a process you want started.** Kubernetes needs a controller, a service contract, and schedulable capacity before it can replace failed application instances.


## Architecture at a Glance

![Terraform state drives cloud provisioning, while an image digest drives a Kubernetes workload release.](images/01-before-after.svg){width=100%}



Think of a Deployment controller as a restaurant manager replacing a missing waiter. The manager still needs a trained replacement and available space. Kubernetes likewise needs a pullable image, valid configuration, and node capacity; it cannot replace missing database records.

## Deployments Own Replica Intent

A Pod is a scheduling unit containing one or more cooperating containers. A Deployment manages ReplicaSets, which maintain the requested Pod count. Deployment changes create a controlled rollout rather than requiring manual Pod replacement.

A Service provides stable discovery and forwards traffic to matching endpoints. Its selector must match the intended Pod labels. A working Pod with the wrong label is invisible to the Service; a wrong broad selector can send traffic to an unrelated workload.

Namespaces organize API objects and policy scope. They are not complete tenant isolation by themselves. RBAC, NetworkPolicy enforcement, admission controls, workload identity, and resource quotas establish additional boundaries.

Use a local disposable cluster before paying for managed capacity. Pin its Kubernetes and node-image versions through your chosen local tool. This chapter's manifests use stable APIs; confirm compatibility with the actual cluster and admission policies.

## The Deployment Contract

Use the Chapter 6 image published by Chapter 10. Replace the image placeholder with its verified registry digest. The manifest deliberately does not embed a database password or make the API publicly accessible.

### First, Read the Smallest Contract

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-api
spec:
  replicas: 2
```

This is the controller intent, not a deployable manifest. The complete Deployment below adds selectors, the Pod template, probes, resource budgets, and security settings.

### namespace.yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: orders
  labels:
    pod-security.kubernetes.io/enforce: restricted
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-api
  namespace: orders
automountServiceAccountToken: false
```

Restricted Pod Security checks container security settings, not application authentication or all network behavior. Pin admission policy versions when managing cluster upgrades so enforcement changes are reviewed rather than accidental.

### deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-api
  namespace: orders
spec:
  replicas: 2
  revisionHistoryLimit: 3
  progressDeadlineSeconds: 120
  selector:
    matchLabels:
      app: orders-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: orders-api
    spec:
      serviceAccountName: orders-api
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: api
          image: REGISTRY/orders-api@sha256:REPLACE_DIGEST
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: PORT
              value: "8080"
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 128Mi
          startupProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 2
            failureThreshold: 30
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
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
          volumeMounts:
            - name: temporary
              mountPath: /tmp
      volumes:
        - name: temporary
          emptyDir:
            sizeLimit: 16Mi
```

A digest placeholder is not deployable configuration. Replace it deliberately and validate the resulting manifest. The fixture has no database dependency; a real order API must define how readiness behaves when its transaction path is unavailable.

### service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: orders-api
  namespace: orders
spec:
  type: ClusterIP # Keep exposure inside the cluster for this lab.
  selector:
    app: orders-api
  ports:
    - name: http
      port: 80
      targetPort: http
```

A ClusterIP Service is not an internet endpoint. Public routing requires an intentionally configured ingress or gateway, TLS, DNS, and authentication. Do not switch to NodePort to bypass an unresolved exposure design.

## Probes Have Different Jobs

Startup probes protect a slow initialization period from premature liveness failure. Readiness controls whether an endpoint should receive Service traffic. Liveness decides whether the process should restart.

Do not make liveness depend on every external service. A temporary database outage could restart every API replica, add connection storms, and erase useful diagnostic context. Readiness also needs care: removing every endpoint during a recoverable dependency incident may change client behavior and amplify retries.

Set probe timeouts and thresholds from measured startup and response behavior. A default that happened to work on a laptop is not a capacity-tested contract. Monitor probe failures separately from application request failures.

## Requests Are Scheduling Inputs

CPU and memory requests tell the scheduler how much capacity the workload needs. Limits constrain execution behavior: memory exhaustion can trigger an OOM kill, and CPU limits can throttle work. These values are starting measurements, not a universal production recommendation.

A rollout with `maxSurge: 1` needs spare schedulable capacity for an additional Pod. If the cluster has no headroom, the new Pod may remain Pending while old replicas continue running. Check scheduling events rather than assuming the deployment is stuck mysteriously.

Two replicas on the same node do not provide node-failure resilience. Add topology-spread or anti-affinity rules and enough nodes to satisfy them. Hard constraints can also block scheduling, so design the cluster capacity and placement rules together.

## Apply and Inspect

```bash
kubectl config current-context
kubectl apply --dry-run=server -f namespace.yaml
kubectl apply -f namespace.yaml
kubectl apply --dry-run=server -f deployment.yaml -f service.yaml
kubectl apply -f deployment.yaml -f service.yaml
kubectl -n orders rollout status deployment/orders-api --timeout=120s
kubectl -n orders get pods -o wide
kubectl -n orders get endpointslices
```

Server-side dry-run needs the Namespace to exist before validating namespaced objects against it. It validates API and admission behavior, not image availability or functional readiness. Confirm the image can be pulled with the configured registry authentication.

Use a temporary local port forward for a controlled test:

```bash
kubectl -n orders port-forward service/orders-api 8080:80
# In another terminal:
curl --fail http://127.0.0.1:8080/readyz
```

Port forwarding demonstrates access through an administrative tunnel, not public routing, load balancing under real traffic, or firewall enforcement. Test the intended user path separately when adding ingress.

Delete one synthetic API Pod and verify the ReplicaSet creates a replacement. Then test a node failure in a disposable multi-node cluster. Compare the recovery delay with your availability objective and record unschedulable conditions.

## Termination Is Part of Correctness

Kubernetes sends termination signals and eventually forces process exit after the grace period. The application must stop taking new work and handle unfinished operations safely. Endpoint updates and external load balancers introduce propagation delays; graceful shutdown must account for real routing behavior.

Workers need durable claims, bounded lease behavior, and idempotent side effects. A replacement worker may encounter work interrupted by a forced termination. A replica count alone does not prevent duplicate execution or lost acknowledgement.

Secrets should come from a reviewed secret-management integration or protected Kubernetes Secrets. Base64 encoding is not encryption. Restrict read permissions, configure encryption at rest where required, and avoid granting the API broad access to the Kubernetes API.

Configuration changes need explicit rollout behavior. Updating a ConfigMap does not universally restart a Deployment or make every process reread its values. Record image and configuration revisions together.

## State and Ownership

Keep workload manifests in Git, cluster runtime state under Kubernetes control, and cloud resource ownership under Terraform. Do not have Terraform and a separate deployment system fight over the same field without a documented ownership contract.

A namespace deletion can remove namespaced workload objects; it is not a safe generic rollback. Persistent data and cloud resources may survive or be deleted depending on their policies. Review cleanup across API, volume, and cloud boundaries.

The acceptance result is a maintained workload with tested service discovery, readiness, replacement, and shutdown. “The Pod is Running” is only a process observation.

## Troubleshoot from Ownership to Traffic

When an API is unavailable, start with the Deployment's desired and available replica counts. Inspect rollout conditions and Pod events before looking at application logs. An unschedulable Pod, failed image pull, admission rejection, and crashing process need different fixes.

Next inspect readiness and Service selectors. Confirm EndpointSlices contain the expected ready addresses. A Service with no endpoints can be a label problem even when every container runs normally. A Service with endpoints can still fail because network policy or destination ports are wrong.

Then test the actual application path with an approved diagnostic identity. Keep administrative port forwarding separate from the user traffic path. It can help isolate process behavior but can bypass parts of the network architecture being investigated.

Finally inspect configuration and dependencies. Compare image digest and configuration revision against the release record. Avoid editing a running Pod to repair configuration: the next replacement will erase that change and restore the declared mistake.

Capture evidence before deleting everything. A restart can remove useful timing and crash context without fixing the underlying dependency. The controller will reproduce the same failure until its desired configuration or operating environment becomes correct.

A good runbook follows these boundaries in order and names the owner responsible for each one.

::: {.callout .protip}
Use controllers, accurate readiness, and schedulable capacity to replace failed workloads.
:::

::: {.callout .takeaways}
- **Use controllers for workloads that must be replaced.**
- **Services discover matching ready endpoints; labels are part of the contract.**
- **Probes, scheduling requests, and limits solve different problems.**
- **Replica count needs placement and capacity to provide resilience.**
- **Validate termination, identity, and configuration behavior.**
- **Keep cloud and cluster ownership boundaries explicit.**
:::

## References

- Deployments: [Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- Pod lifecycle: [Documentation](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
