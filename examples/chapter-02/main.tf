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
