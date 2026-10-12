# Chapter 20: Connect Clouds Carefully: Identity, Routing, and Data Boundaries

::: {.callout .failure}
## The Tunnel Was Up; Traffic Went Nowhere

The AWS-Azure VPN reports established tunnels. The application still cannot reach the recovery database. Both clouds use `10.0.0.0/16`, so hosts treat the destination as local rather than sending it across the intended route.

The network dashboard is green because tunnel establishment succeeded. The application path remains wrong. **Connectivity is an end-to-end route and authorization contract, not a tunnel-status icon.**
:::

## Architecture at a Glance

![The tunnel, return route, DNS, and identity checks all participate in a working transaction.](images/20-cross-cloud.svg){width=100%}



## Allocate Addresses Before Connecting

Reserve non-overlapping ranges for each VPC/VNet, Pod network, Service network, administrative network, and control-plane range. Check existing offices, vendor networks, acquired environments, and future expansion, not just two new cloud diagrams.

| Scope | Example allocation | Ownership |
|---|---|---|
| AWS production VPC | 10.50.0.0/16 | AWS platform root |
| Azure recovery VNet | 10.80.0.0/16 | Azure platform root |
| Azure overlay Pods | 10.81.0.0/16 | AKS configuration |
| Azure Services | 10.82.0.0/16 | AKS configuration |
| GCP nodes | 10.90.0.0/20 | GCP network root |
| GCP Pods | 10.92.0.0/16 | GKE configuration |

These are book allocations, not permission to use them without checking your organization. VPN address translation can sometimes accommodate overlap, but adds complexity to routing, DNS, logging, and policy. Avoid it when deliberate address planning is possible.

## Choose the Routing Protocol Explicitly

AWS Site-to-Site VPN can use static routing or BGP depending on the chosen architecture. Azure gateway settings, tunnel endpoints, and route propagation must match. Define who advertises which prefixes and how withdrawal behaves during failure.

AWS commonly provides two tunnels per VPN connection. A single static Azure public endpoint example does not automatically implement a fully redundant Azure active-active architecture. Engineer both peers and failover paths according to the selected gateway modes.

The AWS Customer Gateway resource describes the remote peer. It is not a running router and does not configure Azure. The VPN connection provisions the AWS side; Azure local-network gateway and connection configuration complete the other side.

## AWS Static-Routing Example

Use a separate connectivity root with the approved AWS provider and remote state. The Azure gateway public IP must already exist and be stable. This example is a static-route lab, not a complete production redundant VPN.

### vpn.tf

```hcl
variable "vpc_id" { type = string }
variable "private_route_table_ids" { type = set(string) }
variable "azure_gateway_public_ip" { type = string }
variable "azure_network_cidr" {
  type    = string
  default = "10.80.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.azure_network_cidr))
    error_message = "Supply a valid IPv4 Azure network CIDR."
  }
}
resource "aws_vpn_gateway" "aws" {
  vpc_id = var.vpc_id
  tags = { Name = "orders-cross-cloud" }
}
resource "aws_customer_gateway" "azure" {
  bgp_asn    = 65020 # Required API field; routing here remains static.
  ip_address = var.azure_gateway_public_ip
  type       = "ipsec.1"
}
resource "aws_vpn_connection" "azure" {
  vpn_gateway_id      = aws_vpn_gateway.aws.id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = true
  # Generated tunnel keys are sensitive outputs/state; do not log them.
}
resource "aws_vpn_connection_route" "azure" {
  destination_cidr_block = var.azure_network_cidr
  vpn_connection_id     = aws_vpn_connection.azure.id
}
resource "aws_route" "azure" {
  for_each               = var.private_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = var.azure_network_cidr
  gateway_id             = aws_vpn_gateway.aws.id
}
```

Supply route-table identifiers as known configuration values or through a map with stable keys if outputs are unknown at plan time. A set of newly created unknown IDs may be unsuitable for `for_each`; preserve stable topology keys when integrating this snippet with network creation.

On Azure, configure the selected VPN gateway, remote AWS tunnel addresses, address spaces, and compatible IKE/IPsec settings. Deliver pre-shared keys through a protected process. Do not copy the entire AWS-generated customer-gateway configuration into a public issue.

## DNS Is a Separate Cross-Cloud System

A network route does not teach an AWS resolver how to resolve a private Azure database name. Use supported inbound/outbound resolver endpoints and conditional forwarding for the required domains. Scope rules to avoid loops and accidental forwarding of unrelated names.

Test resolution from the real application environment. A laptop using a different resolver can produce a false positive. Record the returned address, resolver path, TTL, and expected private zone.

Keep service names stable where appropriate, but do not hide write ownership in a DNS alias. A database name resolving to a secondary does not prove it is writable or sufficiently current. Identity and promotion checks remain separate.

DNS availability is part of recovery. If conditional forwarding depends on the primary cloud, the secondary may lose name resolution during the exact incident it must survive. Maintain independently usable recovery names and procedures.

## FortiGate and Return Paths

Cross-cloud traffic may traverse an inspected path, but only if forward and return routes enforce it. Place FortiGate or the selected inspection service deliberately and test asymmetric routing, failover, and bypass prevention.

Stateful inspection can fail when a return packet reaches another appliance without the required session state. Cloud gateway routing, appliance HA, and NAT choices must be compatible. Do not add a default route to an appliance and assume all peering or VPN traffic will traverse it.

Constrain management access separately from data-plane traffic. Back up firewall policy and VPN configuration securely; exports may contain keys. Test license and image availability in the recovery cloud.

## Data Gravity and Cost

Every cross-cloud call adds latency, failure modes, and possible egress charges. A chatty API talking to a remote database can suffer even when individual round trips appear acceptable. Measure transactions, not just ping latency.

Prefer keeping tightly coupled transactional work near its data. Replicate or transfer selected data through a defined contract rather than making every request depend on a WAN database connection. Replication still needs encryption, identity, retention, and monitoring.

Budget bandwidth for steady-state replication, initial seeding, catch-up after interruption, backups, and game-day traffic. A VPN sized for ordinary requests can take days to catch up after a large outage. Review cloud gateway limits and data-transfer pricing using current regional details before purchase.

## Architecture Checklist

```markdown
# Cross-Cloud Connectivity Gate
- [ ] All VPC/VNet/Pod/Service ranges checked for overlap
- [ ] Forward and return routes documented at every hop
- [ ] Static routing or BGP selected and peer settings matched
- [ ] Tunnel redundancy and failure detection tested
- [ ] DNS forwarding domains and loop prevention verified
- [ ] Caller and destination permissions scoped
- [ ] Inspection path and bypass denial demonstrated
- [ ] MTU, MSS, throughput, latency, and reconnect behavior measured
- [ ] Pre-shared keys stored outside Git and rotation rehearsed
- [ ] Egress and catch-up bandwidth budget approved
- [ ] Recovery DNS and administration survive primary-cloud loss
```

A checked box needs evidence: command output, packet observation, service transaction, and owner. Keep the checklist in the repository, but store sensitive diagnostic material under restricted access.

## Prove the Path and Its Failure Behavior

Test an allowed synthetic request and a denied request from an unauthorized identity. Verify routes and firewall logs, then interrupt one tunnel in a lab and measure reconnection. A successful ICMP test does not prove TLS, database authentication, or application writes.

Exercise MTU-sensitive payloads and long-lived connections. VPN encapsulation can expose packet-size problems that ordinary health probes miss. Observe application retry behavior to prevent reconnection storms.

Keep cloud state roots independent. Connectivity resources may depend on published endpoint identifiers, but recovery of one cloud should not require a live query to the failed cloud's backend. Record those values securely and refresh them through controlled changes.

Destroy connectivity only after stopping dependent replication and traffic. Preserve data checkpoints and configuration backups. A tunnel removal can silently invalidate the secondary's RPO if replication stops without an alert.

## Rotation Can Interrupt the Data Path

A VPN pre-shared-key rotation changes both peers' configuration and can interrupt active sessions. Rehearse tunnel-by-tunnel changes using the selected redundancy design, monitor reconnection, and confirm route behavior before changing the remaining path.

Document which identity can retrieve or change keys on each cloud. Generated VPN configuration and Terraform state may contain sensitive material even when ordinary outputs are masked. Protect exports and delete temporary copies through an approved retention process.

During rotation, verify database replication resumes and catches up. A green tunnel does not prove the worker reconnected or the standby replayed missed WAL. Alert on the data consequence, not merely the network event.

Keep an independent rollback path with the prior approved configuration available only to authorized operators. Once rotation completes, revoke obsolete access and confirm the final configuration matches the intended state. Untracked manual peer changes will otherwise reappear as drift during the next Terraform apply.

Verify rotation alarms reach the operator before beginning; an interrupted replication path without notification can invalidate the recovery objective.

::: {.callout .protip}
Verify both peers, both route directions, and private DNS from the actual caller.
:::

::: {.callout .takeaways}
- **Tunnel establishment is only one part of end-to-end connectivity.**
- **Plan non-overlapping addresses across every network layer.**
- **Configure both peers and both route directions explicitly.**
- **DNS and inspection need independent tested paths.**
- **Measure transaction latency, replication catch-up, and egress cost.**
- **Keep recovery configuration usable without the failed cloud.**
:::

## References

- AWS Site-to-Site VPN: [Documentation](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPC_VPN.html)
- Azure VPN Gateway: [Documentation](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpngateways)
