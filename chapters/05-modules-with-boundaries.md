# Chapter 5: Modules with Boundaries: Reuse Infrastructure Without Coupling Everything

::: {.callout .failure}
## A Development Tag That Replaced Production

The engineer changed `environment = "dev"` to clean up inconsistent tags. The same root generated names for development and production load balancers. A poorly chosen `for_each` key included the environment value, so Terraform interpreted the change as removing old resource addresses and creating new ones.

The reviewed plan contained replacements. The pipeline applied them with production credentials because everything shared one state. A development housekeeping request became a production outage.
:::

A tag update does not inherently destroy a load balancer. The failure was the surrounding address and naming design, combined with an overly broad ownership boundary. **Do not make harmless metadata define resource identity unless replacement is intentional.**


## Root Modules Are Operational Boundaries

A root module is the directory where Terraform executes. It defines provider configuration, backend selection, child-module calls, variables, and outputs. Its state establishes the resources that execution owns.

A child module groups reusable declarations behind an input/output contract. It inherits or explicitly receives provider configurations. Calling it does not create an independent state boundary: its resources remain owned by the calling root.

A child module named `production` inside the development root is still part of that root's state. Directory names do not prevent a development credential from operating on production resources if the provider identity permits it.

Choose roots around change cadence, blast radius, identity, and recovery ownership. Shared networking may deserve one root, while application infrastructure lives elsewhere. Avoid a root for every resource: excessive fragmentation creates dependency orchestration and recovery problems of its own.

## Workspaces Are State Namespaces, Not Security Walls

CLI workspaces provide multiple states for the same configuration. They do not automatically change credentials, isolate cloud accounts, protect backend access, or require a different reviewer.

A workspace can be useful for ephemeral environments with equivalent trust requirements. It is a poor substitute for separating production and developer permissions. An engineer who can select the production workspace and assume its role already crosses the boundary.

This book uses separate development and production roots, accounts, state keys, and apply identities. Shared child modules provide reuse without granting shared administrative scope. The configuration contracts remain similar; the authority does not.

## Keep Modules Small Enough to Explain

A network module should own networking. It should not create a database, configure Jenkins, obtain certificates, and deploy Helm charts because all four eventually use that network.

A stable module has explicit inputs, meaningful outputs, predictable ownership, and a documented upgrade path. Avoid dozens of boolean switches that create incompatible internal modes. If two configurations share only a filename, they may not belong in one module.

Expose identifiers consumers need rather than entire provider objects. Returning a whole subnet object makes callers depend on provider details your module should be free to change. Useful contracts include a VPC ID, subnet-ID map, and address-space documentation.

**Reuse implementation; keep execution and authorization boundaries explicit.**

## Repository Contract

```text
platform/
  modules/
    network/
      versions.tf
      variables.tf
      main.tf
      outputs.tf
  environments/
    dev/
      main.tf
      providers.tf
      backend.tf
      terraform.tfvars.example
    prod/
      main.tf
      providers.tf
      backend.tf
      terraform.tfvars.example
```

Each environment has a different backend key and allowed account ID. Neither commits credentials or local state. A separate root deploys the backend itself.

### modules/network/versions.tf

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.66.0, < 7.0.0"
      # Child contract permits compatible callers; root pins selection.
    }
  }
}
```

### modules/network/variables.tf

```hcl
variable "network" {
  nullable = false
  type = object({
    name = string
    cidr = string
    subnets = map(object({
      cidr = string
      az   = string
    }))
  })
  validation {
    condition     = can(cidrnetmask(var.network.cidr))
    error_message = "Provide a valid IPv4 VPC CIDR."
  }
  validation {
    condition = alltrue([
      for subnet in values(var.network.subnets) :
      can(cidrnetmask(subnet.cidr))
    ])
    error_message = "Every subnet requires a valid IPv4 CIDR."
  }
  validation {
    condition     = length(var.network.subnets) > 0
    error_message = "Define at least one subnet."
  }
}
```

These validations check syntax, not full allocation correctness. Add tests for containment, overlap, and AZ placement. AWS also rejects invalid allocation; discovering those errors at apply time is an expensive feedback loop.

### modules/network/main.tf

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.network.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = var.network.name }
}
resource "aws_subnet" "this" {
  # Stable keys express topology, never mutable display labels.
  for_each = var.network.subnets
  vpc_id   = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  map_public_ip_on_launch = false
  tags = { Name = "${var.network.name}-${each.key}" }
}
```

### modules/network/outputs.tf

```hcl
output "vpc_id" { value = aws_vpc.this.id }
output "subnet_ids" {
  value = {
    for key, subnet in aws_subnet.this : key => subnet.id
  }
}
```

This module deliberately does not establish outbound connectivity. Subnets alone are not a complete application platform. Route-table ownership belongs to an explicitly chosen extension or separate routing module; use Chapter 4 to understand the resources before adding them.

### environments/dev/main.tf

```hcl
module "network" {
  source = "../../modules/network"
  network = {
    name = "orders-dev"
    cidr = "10.40.0.0/16"
    subnets = {
      app_a = { cidr = "10.40.10.0/24", az = "ap-south-1a" }
    }
  }
}
output "vpc_id" { value = module.network.vpc_id }
```

### environments/prod/main.tf

```hcl
module "network" {
  source = "../../modules/network"
  network = {
    name = "orders-prod"
    cidr = "10.50.0.0/16"
    subnets = {
      app_a = { cidr = "10.50.10.0/24", az = "ap-south-1a" }
      app_b = { cidr = "10.50.20.0/24", az = "ap-south-1b" }
    }
  }
}
output "vpc_id" { value = module.network.vpc_id }
```

AZ letters are account-specific mappings; cross-account coordination should use AZ IDs where physical placement matters. The displayed inputs are regional examples, not universal allocations.

## Provider and State Isolation

In each root, keep the exact AWS provider pin from Chapter 2. Configure `allowed_account_ids` with that environment's approved account. Configure backend access to its own state key, and have CI obtain only the corresponding role.

A developer role should fail authorization if pointed at production state. Conversely, production execution must not silently fall back to developer credentials. Validate identity before initialization and again before apply when credential sessions may change.

Local module sources follow the checked-out repository commit. Registry modules require an explicit version. Git module sources should use a reviewed immutable commit reference. The provider dependency lock file does not lock module content.

Maintain an upgrade change that states what changed in the contract, what resources move or replace, and how rollback works. A module refactor can move Terraform addresses without changing AWS infrastructure; use reviewed `moved` blocks instead of destroying and recreating the objects.

```hcl
# Keep this migration in the affected root for upgrading existing state.
moved {
  from = aws_vpc.legacy
  to   = module.network.aws_vpc.this
}
```

## Acceptance and Recovery

Plan development first, then production with production inputs and identity. Do not infer that production is safe because development applied. Capacity, policies, existing resources, and network dependencies can differ.

Test that changing `network.name` updates tags without changing the stable `for_each` keys. Test that deleting `app_b` proposes deleting only the intended subnet and reveals dependent resources before execution. Exercise the account allow-list using a sandbox identity, not a production mutation.

Keep plans and state snapshots protected. If a module upgrade partially applies, inspect which resources succeeded and re-plan from the updated authoritative state. Do not restore an old state merely to make old code appear consistent.

Document which root owns each route, subnet, security group, and endpoint. When transferring ownership between roots, freeze both writers and use a reviewed state-transfer or import procedure. Two roots must never independently reconcile the same object.

Cleanup follows the dependency graph: workloads first, then network consumers, then networking. Backend administration remains independent. A reusable module is successful when another engineer can predict its plan without reading every resource implementation.

## Review a Module as a Product Contract

A module review should answer four questions: what resources it owns, what assumptions its inputs make, what its outputs promise, and what changes can replace existing infrastructure. Put those answers in the module README with a minimal example and migration notes.

Test invalid CIDRs and missing topology entries before testing a happy path. Then exercise a metadata change and a topology change separately. The first should have the documented non-destructive effect; the second should reveal the expected replacement or removal. Preserve the actual plan as restricted evidence.

Treat output changes as interface changes. Renaming a subnet key can break downstream configuration even if AWS resources remain intact. Publish deprecation windows or migration instructions rather than expecting every caller to discover the change during apply.

Ownership is also a contract. If the network module begins creating routes previously managed by another root, coordinate the transfer before either writer applies. The source-code refactor is the easy part; resource adoption and exclusive authority determine whether production survives it.

::: {.callout .protip}
Use stable module keys for identity and separate roots for different trust boundaries.
:::

::: {.callout .takeaways}
- **Child modules organize code; roots establish execution ownership.**
- **Separate production identities, backends, and approvals.**
- **Workspaces do not create security boundaries.**
- **Stable keys preserve identity during metadata changes.**
- **Pin module sources independently of providers.**
- **Review address migrations and recovery paths before upgrades.**
:::

## References

- Terraform modules: [Documentation](https://developer.hashicorp.com/terraform/language/modules)
- Workspaces: [Documentation](https://developer.hashicorp.com/terraform/language/state/workspaces)
