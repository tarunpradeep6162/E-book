# Chapter 3: State Is Infrastructure: Lock It, Protect It, Recover It

## Two Applies, One Broken Production Environment

At 09:12, two engineers start production applies from separate laptops. Each has a copied local state file. One replaces an application instance; the other modifies its security group and deployment outputs.

Neither execution sees the other’s lock. Both operate from an incomplete picture of ownership. A shared-file synchronization tool later overwrites one state copy with the other.

The application loses connectivity. The surviving state records an instance already deleted by the first apply and omits resources created by the second. The team now has both an outage and an unreliable ownership ledger.

This is logical state corruption, even if the JSON still parses. Concurrent writes through an unsafe shared filesystem can also damage the file itself. Do not blame Terraform for coordination your backend never provided.

**One infrastructure ownership boundary requires one authoritative state and one coordinated writer.**

## Remote Storage Alone Is Not Enough

For collaborative infrastructure, a secured remote backend is mandatory. Copies in Git, chat attachments, and synchronized folders do not provide an authoritative, protected coordination mechanism.

State maps Terraform resource addresses to remote identities and stores provider-returned attributes. It is neither application data nor an infrastructure backup. Without it, configuration alone may not identify which existing resources belong to which addresses.

State can contain plaintext passwords, tokens, and private material after decryption. Marking an output `sensitive` suppresses ordinary display; it does not encrypt that value inside state.

**Read access to state is a privileged capability.** Encrypt storage, require TLS, restrict identities, protect local exports, and record access. Saved plans deserve equivalent treatment.

S3 native locking uses a companion object ending in `.tflock`. Terraform coordinates lock acquisition before operations that require exclusive state access. Enable `use_lockfile = true`; locking is not enabled automatically. DynamoDB-based locking is deprecated, so new deployments should use native S3 locking.[1]

A lock protects only clients using the same coordination mechanism and state identity. Two different state keys managing the same resources remain dangerous. So do clients that disable locking or write state directly.

## Bootstrap Without a Circular Dependency

A backend must exist before Terraform initializes it. Therefore, create it in a separate bootstrap root using the Chapter 2 provider requirements, then configure workload roots to use it.

Initially protect bootstrap local state on an encrypted administrative workstation with restricted access and an independently protected backup. For ongoing shared administration, migrate bootstrap state into a separately administered backend whose recovery does not depend on this bucket.

Use distinct identities for backend administration, workload execution, and recovery. The workload role may read and update one state object; it must not delete the bucket, disable versioning, or schedule deletion of its KMS key.

### backend-bootstrap.tf

The following belongs in the bootstrap root, not the workload root. Supply the approved account and existing execution-role name through non-secret inputs.

```hcl
variable "account_id" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply a 12-digit AWS account ID."
  }
}

variable "state_role_name" {
  type        = string
  description = "Existing, approved workload execution role."
  nullable    = false
}

provider "aws" {
  region              = "ap-south-1"
  allowed_account_ids = [var.account_id]
}

locals {
  bucket_name = "orders-prod-state-${var.account_id}"
  state_key   = "prod/aws/orders/terraform.tfstate"
}

resource "aws_kms_key" "state" {
  description             = "Terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # Enable same-account IAM delegation; this is not public access.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableAccountIAM"
      Effect    = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action   = "kms:*"
      Resource = "*" # In a key policy, refers to this key.
    }]
  })

  lifecycle {
    prevent_destroy = true # Guardrail, not an IAM boundary.
  }
}

resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    # Object-level encryption context enables narrower KMS conditions.
    bucket_key_enabled = false

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.state.arn,
        "${aws_s3_bucket.state.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  value = aws_kms_key.state.arn
}
```

Keep the Chapter 2 `terraform.required_providers` block, but replace its provider configuration with the bootstrap provider above; do not declare two default AWS providers.

`prevent_destroy` blocks covered destruction while the declaration remains present. Removing the resource declaration, using another administrative identity, or deleting through AWS can defeat that guardrail. IAM and organizational controls must enforce the actual boundary.

Versioning preserves previous object versions; it does not prevent an administrator deleting those versions. KMS protection also fails operationally if recovery identities cannot decrypt backups. Test recovery permissions before an incident.

### backend.tf

Create this file only in the workload root:

```hcl
terraform {
  backend "s3" {
    # Replace both example identifiers with bootstrap outputs.
    bucket = "orders-prod-state-123456789012"
    key    = "prod/aws/orders/terraform.tfstate"
    region = "ap-south-1"

    encrypt      = true
    use_lockfile = true

    kms_key_id = "arn:aws:kms:ap-south-1:123456789012:key/REPLACE_WITH_KEY_ID"
    allowed_account_ids = ["123456789012"]
  }
}
```

Backend blocks cannot reference ordinary variables, locals, or resource outputs. Copy verified bootstrap outputs or provide non-secret partial configuration at initialization. Never put credentials into backend arguments: configuration can persist in working directories and plan artifacts.

Native locking is implemented by Terraform’s S3 backend, not the AWS provider. Use Terraform 1.10 or later, with an exact reviewed CLI version in every execution environment.

## Give the Writer Only Its State

Add `state-writer-policy.tf` to the bootstrap root. This identity policy assumes the execution role already exists in the same account.

```hcl
resource "aws_iam_policy" "state_writer" {
  name = "orders-prod-state-writer"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListDedicatedBackend"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid    = "ReadWriteOneState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.state.arn}/${local.state_key}"
        ]
      },
      {
        Sid    = "ManageOnlyItsLock"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.state.arn}/${local.state_key}.tflock"
        ]
      },
      {
        Sid    = "UseStateKeyThroughS3"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.state.arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.ap-south-1.amazonaws.com"
            "kms:EncryptionContext:aws:s3:arn" = [
              "${aws_s3_bucket.state.arn}/${local.state_key}",
              "${aws_s3_bucket.state.arn}/${local.state_key}.tflock"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "state_writer" {
  role       = var.state_role_name
  policy_arn = aws_iam_policy.state_writer.arn
}
```

Bucket listing is scoped to this dedicated backend bucket; object permissions are scoped to the exact state and lock keys. This policy intentionally excludes state deletion and historical-version access. Use only the default workspace with this example; alternate workspaces change object paths.

This is backend access, not permission to provision application infrastructure. Attach independently reviewed workload permissions to the execution identity. Other policies, permission boundaries, service-control policies, and the KMS key policy still affect effective access.

SSE-KMS requires appropriate key permissions as well as S3 permissions.[2] If enabling S3 Bucket Keys later, review the encryption-context conditions because the context changes.

## Migrate and Prove Coordination

Freeze writes before migration. Back up existing local state into a restricted, encrypted location and authenticate as the intended workload identity.

```bash
# Run in the workload root after bootstrap completes.
umask 077
terraform init -migrate-state

# Confirm migration did not introduce ownership changes.
terraform plan -lock-timeout=60s
```

Review the migration prompts; do not use unattended force-copy as a convenience. Confirm the expected key exists, encryption uses the expected KMS key, and versioning is enabled.

In an isolated lab, hold a state lock using one execution and verify a second execution waits or fails with lock information. Do not race production applies to demonstrate locking.

Test that the writer can create and remove its lock but cannot delete state, access another state key, or administer the KMS key. Record the identity, backend key, and observed result.

Do not set `-lock=false` to get past contention. A blocked apply is protecting the ownership ledger.

## State Recovery Runbook

**Recover the relationship between state and infrastructure, not merely an older file.**

1. Freeze CI and administrative writes. Verify no active writer remains; identify the account, region, bucket, and key.
2. Preserve the current object and incident evidence using the recovery identity. Store exports securely.
3. Inspect available state versions and select a candidate based on deployment records, resource identities, lineage, and serial.
4. Compare that candidate with actual infrastructure. An older state may omit resources created after its snapshot.
5. Restore only under an approved recovery procedure, then review a normal plan without applying it.

Example inspection commands, executed with a recovery role authorized for historical reads:

```bash
umask 077
export STATE_BUCKET="orders-prod-state-123456789012"
export STATE_KEY="prod/aws/orders/terraform.tfstate"

aws s3api list-object-versions   --bucket "$STATE_BUCKET" --prefix "$STATE_KEY"

# Replace VERSION_ID; candidate.json contains sensitive state.
aws s3api get-object   --bucket "$STATE_BUCKET" --key "$STATE_KEY"   --version-id VERSION_ID candidate.json

terraform state pull > current.json

# Stops on incompatible lineage or an older serial.
terraform state push candidate.json
```

A rejected push is a safeguard, not a reason to add `-force`. Use reviewed imports, address moves, or a formally authorized state-restoration procedure where rollback of state is actually necessary. Preserve both snapshots.

For a stale lock, verify its owner has stopped and use `terraform force-unlock LOCK_ID` only against the confirmed backend. Never delete a live lock to unblock a deadline.

Complete recovery by reviewing `terraform plan`, resolving unexpected deletions or replacements, and testing application behavior. Record lost ownership information and remediation. State recovery does not restore lost database records.

## Key Takeaways

- **Use one authoritative, locked backend per ownership boundary.**
- **Treat state and plans as sensitive, even when outputs are masked.**
- **Enable native S3 locking explicitly; DynamoDB locking is deprecated.**
- **Separate bootstrap, workload, and recovery authority.**
- **Scope state writes and lock deletion independently.**
- **Versioning and KMS need tested recovery access.**
- **Never force past state or lock safeguards without investigation.**

## References

[1] HashiCorp S3 backend: [Documentation](https://developer.hashicorp.com/terraform/language/backend/s3)
[2] AWS SSE-KMS: [Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html)

