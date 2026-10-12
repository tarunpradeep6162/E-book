# Chapter 2: Terraform Without Guesswork: Build a Reproducible Foundation

## The Apply That Removed the Emergency Fix

At 11:40, customers stop receiving order confirmations. During yesterday’s incident, an engineer added an AWS security-group rule through the console so the API could reach PostgreSQL on port 5432. Another engineer changed the application’s database endpoint manually.

Neither change reached Git. This morning’s routine Terraform plan proposed removing the extra rule from a security group whose rules were managed inline. The reviewer saw a small network change and approved it.

The apply completed successfully. Database connections failed, retries saturated the API, and order processing stopped.

Terraform did not misunderstand the emergency fix. The team misunderstood ownership: configuration still declared the previous rules, and reconciliation removed the console-added access.

**A successful apply proves that Terraform completed its requested operations. It does not prove that your architecture still works.**

## Configuration, State, and Reality

Terraform works with three distinct inputs:

| Input | Responsibility |
|---|---|
| Configuration | Declares intended infrastructure and relationships |
| State | Associates Terraform addresses with remote objects and records attributes |
| Provider reads | Observe supported attributes of real infrastructure |

During an ordinary plan, Terraform reads tracked objects through their providers and compares refreshed observations with configuration. It then proposes actions that reconcile the differences. State supplies identity: `aws_s3_bucket.foundation` maps to a particular AWS bucket.

Terraform does not scan an account and adopt every object. An independently created security group remains outside this configuration’s ownership until explicitly imported and represented appropriately.

Drift behavior also depends on resource semantics. An inline security-group definition can reconcile its managed rule set; an individually managed rule does not imply ownership of every other rule. Read the provider’s ownership model before predicting what Terraform will remove.

When console drift appears, choose deliberately: incorporate the change into configuration, reverse it, or transfer ownership through a reviewed procedure. Never assume that refreshing state makes the configuration agree with the emergency change.

```bash
# Inspect observed drift without proposing configuration-driven repairs.
terraform plan -refresh-only

# Compare configuration with refreshed infrastructure before authorizing writes.
terraform plan -out=reviewed.tfplan
terraform show reviewed.tfplan
```

Refresh-only apply updates state and outputs without intentionally changing remote infrastructure. It does not rewrite your HCL. Review it as a state operation, not a fix for missing declarations.[1]

## Terraform Executes a Graph, Not a Script

Terraform loads the root directory’s configuration files together. Naming a file `01-network.tf` does not make it execute before `02-storage.tf`.

References establish dependency edges. An object referencing its bucket identifier must wait for that bucket to exist. Independent resources can execute concurrently.

Some values are unknown until apply because their producers do not exist yet. Those unknowns propagate through dependent expressions; they are not evidence that Terraform has ignored your configuration.

Use `depends_on` for a hidden behavioral prerequisite that has no natural value reference. For example, writing an object must wait for bucket versioning even though the object needs only the bucket identifier.

**Prefer expression references; use explicit dependencies narrowly.** Broad module-level dependencies can make plans unnecessarily conservative and increase unknown values.[2] Ordering also does not guarantee application readiness or eliminate eventual consistency.

## Providers, Resources, and Data Sources

A provider implements the API operations Terraform uses to read and manage infrastructure. `required_providers` declares its source and compatible versions; the `provider` block configures its region, authentication context, and other behavior.

A resource declares something this configuration owns. A data source reads information without taking lifecycle ownership of the queried object. In this chapter, resources manage a private S3 bucket; `aws_caller_identity` reads the execution account.

Data sources are not automatically reproducible inputs. A query for the newest machine image can resolve differently next week, despite unchanged HCL. Use stable identifiers or deliberate update procedures where deployment reproducibility requires them.

## Hands-On: A Guarded Terraform Root

Create the starter under the development AWS root from Chapter 1:

```bash
cd platform
mkdir -p infra/environments/dev/aws/foundation
cd infra/environments/dev/aws/foundation
```

The project provisions a private, versioned, encrypted bucket and a non-secret architecture marker. It demonstrates production-oriented input and dependency controls without exposing a service publicly.

This is not the Terraform state bucket. Chapter 3 introduces the remote backend; this isolated lab uses local state and must not become a shared production apply root.

### providers.tf

```hcl
terraform {
  # Bound CLI compatibility; pin the exact CLI in your team's runner image.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Exact root-module pin: upgrades require an explicit reviewed change.
      version = "= 6.66.0"
    }
  }
}

provider "aws" {
  region = var.deployment.region

  # Fail closed when the shell authenticates to the wrong AWS account.
  allowed_account_ids = [var.deployment.account_id]

  # Credentials come from the standard credential chain, never this file.
  default_tags {
    tags = {
      Project     = var.deployment.project
      Environment = var.deployment.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

The provider version is an explicit baseline, not a request for “latest.” Before adopting it, review its release notes and validate it with your organization’s CLI and policies.

The CLI range rejects unsupported major versions but does not pin one binary. Record an exact CLI version in your development tooling and CI image. The provider lock file does not lock Terraform itself.

### variables.tf

```hcl
variable "deployment" {
  description = "Reviewed deployment identity and placement."
  nullable    = false

  # One structured contract prevents unrelated account/region defaults.
  type = object({
    account_id  = string
    region      = string
    environment = string
    project     = string
  })

  validation {
    condition     = can(regex("^[0-9]{12}$", var.deployment.account_id))
    error_message = "account_id must contain exactly 12 digits."
  }

  validation {
    # This is an organization allow-list, not AWS's complete region list.
    condition = contains(
      ["ap-south-1", "ap-southeast-1"],
      var.deployment.region
    )
    error_message = "region must be ap-south-1 or ap-southeast-1."
  }

  validation {
    condition = contains(
      ["dev", "staging", "prod"],
      var.deployment.environment
    )
    error_message = "environment must be dev, staging, or prod."
  }

  validation {
    # Constrain project naming before constructing resource identifiers.
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.deployment.project))
    error_message = "project must be 3-20 lowercase letters, digits, or hyphens, starting with a letter."
  }
}
```

An object type validates structure; the validation blocks enforce domain rules. `can(regex(...))` turns a nonmatching expression into a controlled validation failure.

These checks reject known invalid inputs before resource creation. They cannot prove sufficient IAM permissions, available capacity, or globally unique resource names. Input validation reduces preventable failures; it does not replace planning and service-level checks.

### main.tf

```hcl
data "aws_caller_identity" "current" {}

locals {
  # Account, region, and environment reduce collisions; S3 names remain global.
  bucket_name = join("-", [
    var.deployment.project,
    var.deployment.environment,
    data.aws_caller_identity.current.account_id,
    var.deployment.region,
    "foundation"
  ])
}

resource "aws_s3_bucket" "foundation" {
  bucket = local.bucket_name

  # Never empty stored objects automatically to make destruction succeed.
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "foundation" {
  bucket = aws_s3_bucket.foundation.id # Implicit dependency on the bucket.

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "foundation" {
  bucket = aws_s3_bucket.foundation.id

  versioning_configuration {
    status = "Enabled" # Retain previous object versions after overwrite.
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "foundation" {
  bucket = aws_s3_bucket.foundation.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Explicit SSE-S3 baseline; no secrets in HCL.
    }
  }
}

resource "aws_s3_object" "architecture_marker" {
  bucket       = aws_s3_bucket.foundation.id # Natural implicit dependency.
  key          = "architecture/foundation.json"
  content_type = "application/json"

  content = jsonencode({
    project     = var.deployment.project
    environment = var.deployment.environment
    purpose     = "Non-secret foundation metadata"
  })

  # Hidden prerequisites: the bucket ID alone conveys none of these controls.
  depends_on = [
    aws_s3_bucket_public_access_block.foundation,
    aws_s3_bucket_versioning.foundation,
    aws_s3_bucket_server_side_encryption_configuration.foundation
  ]
}
```

The bucket reference establishes existence ordering. The explicit edges establish security and persistence prerequisites before writing the marker.

Versioning is not immutable backup storage. SSE-S3 is encryption at rest, not a customer-managed key policy. Sensitive workloads may require KMS controls, TLS-enforcing bucket policies, retention enforcement, and independently protected recovery copies.

## Credentials Are Execution Inputs

Authenticate locally through an approved AWS IAM Identity Center profile:

```bash
aws sso login --profile platform-dev
export AWS_PROFILE=platform-dev
aws sts get-caller-identity
```

Verify the returned account before planning. The provider’s account allow-list adds another guardrail; it does not grant permission.

Use a development-scoped role authorized only for the lab’s S3 operations and account-identity lookup. CI should obtain short-lived role sessions through supported federation or workload identity rather than reuse a developer’s credentials.

Do not write access keys into HCL, variable files, shell scripts, or Git. Secret masking does not prevent exposure through state, logs, or saved plans. Provider credentials and backend credentials also have separate configuration paths; protect both.

## Lock Dependencies and Review Execution

Create `terraform.tfvars`, replacing the example account with your sandbox account:

```hcl
deployment = {
  account_id  = "123456789012"
  region      = "ap-south-1"
  environment = "dev"
  project     = "orders"
}
```

Initialize and record provider selections:

```bash
terraform init

# Record package checksums for the team's actual execution platforms.
terraform providers lock   -platform=linux_amd64   -platform=darwin_arm64

terraform fmt -check -recursive
terraform validate
terraform plan -out=reviewed.tfplan
terraform show reviewed.tfplan
```

Commit `.terraform.lock.hcl`. Constraints specify acceptable versions; the lock file records selected provider versions and package checksums. It does not lock remote modules, which need their own version or commit constraints.[3]

After committing the lock, CI should use `terraform init -lockfile=readonly`. Perform intentional upgrades in a separate change with `terraform init -upgrade`; an exact provider pin must first be changed.

Review creation, deletion, replacement, IAM effects, and network effects before running:

```bash
# Apply the reviewed saved plan rather than generating a different plan.
terraform apply reviewed.tfplan

# Confirm convergence; inspect any unexpected remaining actions.
terraform plan -detailed-exitcode
```

Detailed exit codes are 0 for no changes, 1 for an error, and 2 for proposed changes. A saved plan is sensitive and time-bound: concurrent infrastructure changes still require coordination and fresh review.

Terraform is not a transaction across AWS resources. An apply can partially succeed before failing; inspect state and reality, correct the cause, and re-plan. Do not assume automatic rollback.

For this lab, preserve local state, exclude it and plans from Git, and keep a single authorized operator. Cleanup requires deliberately removing the marker’s current and historical versions before destroying the bucket; `force_destroy = false` prevents automatic data purging.

## Key Takeaways

- **Configuration, state, and observed infrastructure serve different roles.** Refreshing state does not adopt console changes into HCL.
- **Terraform executes dependencies, not file order.** References create natural edges; explicit dependencies describe hidden prerequisites.
- **Resources own lifecycle; data sources read information.** Mutable queries can weaken reproducibility.
- **Pin dependencies deliberately.** Commit provider locks and independently pin CLI and module versions.
- **Validate contracts early.** Typed objects and regex checks prevent avoidable deployment mistakes.
- **Treat credentials, state, and plans as sensitive.** Use scoped short-lived identities and verify the target account.
- **Review effects, not just success messages.** Apply approved plans, verify convergence, and test application behavior.

## References

[1] HashiCorp: [Documentation](https://developer.hashicorp.com/terraform/tutorials/state/refresh)
[2] HashiCorp: [Documentation](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)
[3] HashiCorp: [Documentation](https://developer.hashicorp.com/terraform/language/files/dependency-lock)

