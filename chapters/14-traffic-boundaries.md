# Chapter 14: Traffic Has Boundaries: TLS, Network Policies, and FortiGate

## One Container, Every Database

An attacker exploits an exposed API dependency. From that container, the attacker connects to billing, administration, and the database because the cluster has no enforced traffic policy. Network reachability expands a single application flaw into a platform incident.

A VPC perimeter firewall did not see the Pod-to-Pod path. The security diagram showed a firewall icon but never demonstrated packet traversal. **Controls protect traffic only where they are actually enforced.**

## North-South and East-West Are Design Categories

Ingress or gateway infrastructure commonly handles traffic entering the application from outside the cluster. NetworkPolicies constrain selected Pod ingress and egress. They can also affect external destinations; they are not restricted to east-west traffic alone.

A Kubernetes Ingress object needs an installed controller and an appropriate ingress class. It is a routing declaration, not an automatic TLS endpoint or authorization layer. Configure DNS, certificate issuance, redirect behavior, request limits, and authentication explicitly.

NetworkPolicies require a network implementation that enforces them. Applying YAML to an unsupported cluster can succeed while traffic remains unrestricted. Verify implementation compatibility, then run positive and negative connectivity tests.

Policy rules are additive. A default-deny policy selects traffic for isolation; another allow policy can permit it. There is no general ordering where a later deny overrides all earlier allows. Labels are security-relevant selectors and must be protected from arbitrary mutation.

## Establish Default Deny

Apply this to the backend namespace after inventorying its dependencies. An unplanned production default deny can cause an outage by blocking DNS, secret retrieval, monitoring, or health paths.

### default-deny.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: backend
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

This does not cover every possible host-network or infrastructure packet path. Review your CNI's behavior, node traffic exceptions, and cloud security-group interactions. NetworkPolicy is one layer in the trust model.

### allow-frontend.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: orders-api
  policyTypes: [Ingress]
  ingress:
    - from:
        # One peer containing both selectors means namespace AND Pod label.
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: frontend
          podSelector:
            matchLabels:
              app: orders-frontend
      ports:
        - protocol: TCP
          port: 8080
```

If the namespace and Pod selectors appear as separate entries under `from`, they become alternative allowed peers rather than the intended intersection. This small YAML difference can widen access substantially.

The frontend namespace also needs an outbound permission if it has default-deny egress. Policy permission at the backend does not override a denied sender path.

### allow-api-egress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-required-egress
  namespace: backend
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
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: data
          podSelector:
            matchLabels:
              app: postgres
      ports:
        - {protocol: TCP, port: 5432}
```

Verify the DNS labels and topology in your cluster. Node-local DNS and managed DNS paths may differ. A managed external database is not selected by a Pod label; use an appropriate network design and policy mechanism for its actual addresses.

The database namespace needs matching ingress permission. Default-deny policy on both ends creates an explicit communication contract rather than relying on one namespace's behavior.

## TLS Is an Identity Boundary

Terminate TLS at a reviewed entry point and decide whether to re-encrypt to the backend. Validate certificates and service identities on internal connections where the threat model requires it. “Private network” does not justify disabling database TLS verification.

Certificate lifecycle includes issuance, renewal, trust-store updates, and emergency replacement. Monitor expiry and renewal errors. A certificate controller's Kubernetes permissions and cloud DNS permissions should be narrowly scoped.

Keep application authorization separate: TLS authenticates selected endpoints and protects transport, while the API must still authenticate callers and enforce order access. A valid encrypted request can still be malicious.

## FortiGate Must Be on the Actual Route

FortiGate-VM can provide inspected routing at the VPC edge or between connected networks. Its deployment requires appropriate licensing, throughput sizing, interface configuration, high availability, and cloud routing integration. Treat these as tested prerequisites, not an automatic free feature.

A conceptual routed inspection path is:

| Source | Destination | Next hop | Required return behavior |
|---|---|---|---|
| Application subnet | Approved external network | Inspection appliance or supported endpoint | Return traffic through the same inspected flow |
| Appliance external path | Internet or VPN peer | Approved gateway | Session-aware return routing |
| Connected cloud | Application subnet | Inspection path | No bypass route to workload subnet |

In AWS, direct appliance routing may target an appliance ENI with source/destination checks disabled when required by the design. Other architectures use Gateway Load Balancer endpoints and appliance mode. These are different implementations; do not mix their routes or assume one example configures both.

High-level FortiGate policy intent is: trusted application zone to approved destination objects, specified services only, logging enabled, and deny everything else. Build address and service objects from the actual allocation plan. Use a separate management interface or path with restricted administrators.

Deep packet inspection of encrypted traffic requires an explicit TLS-inspection design and trusted certificates, with privacy, application compatibility, and failure behavior reviewed. A firewall cannot inspect plaintext inside arbitrary TLS without that arrangement.

## Test Packet Paths

Choose synthetic test Pods in frontend, backend, and an unauthorized namespace. Use a reviewed diagnostic image digest and a nonprivileged identity. Verify frontend-to-API succeeds and unauthorized-to-API fails. Check both UDP and TCP DNS where needed.

```bash
kubectl -n backend get networkpolicy
kubectl -n backend describe networkpolicy allow-frontend-to-api
kubectl -n backend get pods --show-labels
kubectl get namespaces --show-labels
```

A failed request alone does not prove policy enforcement: the destination may be down. Confirm the same destination is reachable from the approved caller during the test. Record firewall logs, CNI observations, and application outcomes together.

For appliance routes, capture the effective route table and demonstrate traffic appears in inspection logs. Test an intentional bypass attempt and asymmetric return route in an isolated environment. Measure MTU, connection establishment, and throughput rather than assuming VPN plus inspection preserves application performance.

## State and Recovery

Version policies, route definitions, certificates' configuration references, and firewall configuration backups. Secret keys and private certificates belong in protected storage. Do not commit exported firewall configurations containing passwords or VPN pre-shared keys.

A policy rollback must identify the exact previous reviewed revision. Removing all NetworkPolicies may restore traffic but also remove the security boundary; use a targeted emergency procedure with owner and expiry.

Recover the firewall's configuration, licenses, routing integration, and administrative identity together. An appliance that boots with default routes is not a restored inspection path. A cluster policy that exists without enforcement is not a restored security boundary.

Application teams own dependency declarations; platform and security teams own enforcement contracts. Keep a reviewed communication matrix so changing a service endpoint does not silently require broadening the network to everywhere.

## Make Dependency Changes Reviewable

Maintain a communication matrix with caller identity, destination identity, protocol, port, purpose, and verification method. When a team adds an external API or moves a database, the change should update that contract and its enforcement together.

Avoid permanent temporary allowances. An emergency broad rule needs a named owner, expiry, monitoring, and removal verification. The incident record should explain what narrower rule replaces it. Otherwise the next audit inherits a network whose real trust boundaries exist only in old chat messages.

For service discovery, distinguish names from enforcement addresses. Standard NetworkPolicy does not universally provide portable DNS-name egress matching. If a platform uses FQDN-aware policy extensions, document their controller, DNS behavior, and cloud-specific portability limits.

Observe both directions when troubleshooting. Source egress, destination ingress, cloud security groups, route tables, and appliance policy may all participate. A policy change at the wrong layer can broaden access without affecting the actual blocked path.

Treat namespace and Pod label mutation as a security capability. A user able to assign trusted labels may place a workload inside an allow selector. Admission and RBAC should align with the label-based model rather than letting any tenant impersonate a permitted caller.

During recovery, validate the restored policy against current allocation and service identity. A firewall configuration from last month can point to retired addresses. Configuration backup is necessary, but successful restoration also requires correct current routes, identities, and tests.

The final evidence should show a working permitted transaction, a denied unauthorized transaction, and the expected enforcement logs. That combination supports the boundary more strongly than either successful access or an isolated timeout alone.

Repeat the negative connectivity test after policy upgrades; successful enforcement last month does not verify the current network implementation.

## Key Takeaways

- **Prove enforcement, not just successful YAML creation.**
- **NetworkPolicies are additive and selector placement matters.**
- **Default deny needs explicit DNS and dependency allowances.**
- **TLS, routing, and application authorization are separate controls.**
- **FortiGate inspection requires tested forward and return paths.**
- **Version and rehearse recovery of policies and appliance configuration.**

## References

- NetworkPolicies: [Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- Fortinet AWS documentation: [Documentation](https://docs.fortinet.com/product/fortigate-public-cloud)
