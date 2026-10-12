# Chapter 19: GCP Without a Rewrite: Test the Limits of Portability

## The Friday Migration Mandate

The CTO asks for a GCP deployment by Friday. The team assumes containers make the migration straightforward. The API starts, then fails because business code expects S3-specific signed URLs, IAM credential discovery, and AWS event payloads.

The image was portable. The application contract was not. **Container portability does not imply service portability.** Identify provider-specific assumptions before estimating the migration, especially in storage, identity, events, and database features.

## Build a Capability Map

| Capability | AWS implementation | GCP implementation | Application consequence |
|---|---|---|---|
| Managed Kubernetes | EKS | GKE | Similar workload APIs; platform behavior differs |
| Image registry | ECR | Artifact Registry | Different identity and repository references |
| Object storage | S3 | Cloud Storage | API and signed-URL semantics may differ |
| PostgreSQL service | RDS | Cloud SQL | Connection, identity, extensions, operations differ |
| Workload authorization | IAM role integration | Workload Identity Federation for GKE | Token and SDK integration changes |

Keep HTTP APIs, event contracts, idempotency keys, and transaction semantics stable where possible. Put object-storage behavior behind a small application interface with explicit error and consistency expectations. Do not build an abstraction that hides every cloud feature indiscriminately.

An adapter needs tests for upload, download, metadata, deletion, retries, signed-URL expiry, and authorization failure. Equivalent method names do not prove equivalent behavior. Review required features such as object versioning, retention, encryption, and event delivery separately.

## Autopilot Changes the Node Ownership Contract

GKE Autopilot manages substantial node provisioning and configuration responsibilities. You still own workload resource requests, placement requirements, supported security settings, identity, network boundaries, data, and cost behavior.

Autopilot admission can enforce or adjust workload settings. A privileged diagnostic DaemonSet that worked on your EKS lab may be rejected. Validate supported workload patterns before deciding the platform is interchangeable.

This example provisions a custom VPC, subnet with secondary ranges, and private Autopilot cluster. It is a separate GCP Terraform root with its own credentials and remote backend. Enable the required project services before provisioning and verify quota and billing.

### gke.tf

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" # Commit the reviewed provider selection.
    }
  }
}
variable "project_id" { type = string }
provider "google" {
  project = var.project_id
  region  = "asia-south1"
}
resource "google_compute_network" "platform" {
  name                    = "orders-platform"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "platform" {
  name                     = "orders-platform"
  region                   = "asia-south1"
  network                  = google_compute_network.platform.id
  ip_cidr_range            = "10.90.0.0/20"
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.92.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.93.0.0/20"
  }
}
resource "google_container_cluster" "platform" {
  name             = "orders-autopilot"
  location         = "asia-south1"
  enable_autopilot = true
  network          = google_compute_network.platform.id
  subnetwork       = google_compute_subnetwork.platform.id
  deletion_protection = true

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.20.0.0/28"
  }
  release_channel {
    channel = "REGULAR"
  }
}
```

Autopilot's managed identity and networking behavior must be checked against the selected provider and service version. Do not add a manually managed node group to this example. A release channel is an upgrade policy, not an immutable forever-version guarantee.

The address allocation includes node, Pod, Service, and control-plane ranges. Ensure none overlaps connected networks. Private nodes need a deliberate route to required external services; Private Google Access addresses selected Google-service access, not arbitrary internet egress. Add approved Cloud NAT or other paths when required.

A private endpoint needs administration from a supported connected environment. Test the agent's route, DNS, identity, and authorization. A credentials command can succeed while the Kubernetes endpoint remains unreachable.

## Authenticate Without Exported Keys

Use Application Default Credentials through an approved local identity or supported workload federation in CI. Avoid downloading a long-lived service-account JSON key as the default pipeline solution.

Separate Terraform provisioning authority from workload identity. A Pod retrieving an object should not receive permission to create networks or administer the project. Restrict who can impersonate privileged service accounts and who can change federation mappings.

Workload Identity Federation for GKE has GKE-specific identity syntax and resource policies. Translate the worker's required capability into a scoped GCP permission and prove the effective identity. Do not reuse the AWS role ARN annotation and expect it to authenticate.

Registry permissions likewise differ. Artifact Registry repositories are regional resources with explicit access policies. Copy the approved image, verify its resulting digest and provenance, and ensure the secondary environment can pull it independently of AWS.

## Deploy the Application Contract

Retrieve cluster credentials from the approved environment:

```bash
gcloud config get-value project
gcloud container clusters get-credentials orders-autopilot \
  --region asia-south1 --project APPROVED_PROJECT
kubectl config current-context
kubectl auth can-i get pods -n orders
```

Confirm project identity before changing anything. Do not rely on an operator's default project left over from another task. Use separate configuration or explicit project arguments in automation.

Render cloud-specific workload values: registry path, secret integration, storage class, identity labels, and ingress configuration. Preserve the same application digest and HTTP behavior where possible. Validate API compatibility through server-side dry-run and functional tests.

Autopilot may require resource declarations and disallow host-level privileges. Test the actual admission response rather than adding exceptions blindly. Security restrictions can expose assumptions your earlier platform tolerated without review.

## Data Portability Has a Recovery Cost

Database portability includes extensions, collation, privileges, connection limits, backup formats, encryption dependencies, and transaction behavior. A PostgreSQL-compatible service name is not proof that an existing dump and workload can move unchanged.

Object storage migration needs inventory, version handling, metadata translation, checksums, deletion semantics, and cutover policy. If URLs were persisted in database rows, moving buckets may require data transformation rather than a single environment-variable change.

Measure bulk migration time and incremental catch-up. Cross-cloud transfer can incur egress charges and take longer than compute provisioning. Data gravity often makes the database and object-store migration the dominant part of the project.

## Test the Limits, Then Record Them

Create a portability matrix listing what ran unchanged, what required new configuration, and what required application changes. For each item, record a verification test and owner. This is more useful than claiming the whole platform is cloud agnostic.

Test allowed and denied network paths, workload identity, image retrieval, storage provisioning, synthetic order processing, and graceful shutdown. Also test what happens when a cloud service rate-limits or returns an authorization error; provider-specific failure behavior can leak through adapters.

Keep GCP state encrypted and scoped in an independently managed remote backend. Back up recovery configuration and test privileged access separately. Cloud provisioning state does not restore Cloud SQL records or object versions.

## Cleanup and Upgrade Responsibility

Deletion protection requires a deliberate reviewed change before cluster destruction. Plan the retention of data volumes, registry images, external addresses, and backups. Managed node removal does not imply every chargeable resource disappears.

Track release-channel upgrades and application compatibility. Managed operations still need maintenance planning, supported API monitoring, and incident procedures. Record which platform actions Google performs and which your team must validate.

The deliverable is an honest GCP deployment and a tested portability boundary. If the migration requires rewriting storage integration, say so early; that is an architectural finding, not a failure of Docker.

## Build Adapter Tests Around Failure Semantics

An object-store adapter should expose a small documented result model: success, missing object, authorization failure, retryable service failure, and invalid request. Test how each cloud SDK maps its errors into that model. Otherwise provider exceptions can leak into business retry logic.

Signed URLs need explicit expiration, allowed method, content constraints, and trust boundaries. A URL generated on one provider may not permit the same headers or upload behavior on another. Validate the actual client workflow rather than only asserting a string was returned.

If storing provider identifiers in order records, distinguish durable business identity from storage location. A migration should be able to change location without changing which customer object the record represents. Record checksums and metadata needed to verify transfer completeness.

Event delivery also needs idempotency. Cloud notification systems can differ in ordering and retry behavior, so the worker must not treat one arrival as proof of one unique operation. Use durable deduplication or transactional state transitions.

These tests define the portability contract. They let the team add a cloud-specific implementation without pretending every managed-service feature is interchangeable or forcing business code to understand every provider's failure syntax.

Treat an adapter exception as a reviewable product limitation with an owner, rather than silently falling back to a different storage behavior.

## Key Takeaways

- **Containers are portable artifacts; managed-service contracts may not be.**
- **Autopilot changes node ownership, not application responsibility.**
- **Use cloud-specific identity, networking, and storage configuration.**
- **Keep application adapters narrow and behaviorally tested.**
- **Include data migration time and egress cost in the plan.**
- **Document verified portability and explicit exceptions.**

## References

- Autopilot: [Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview)
- GKE Workload Identity Federation: [Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
