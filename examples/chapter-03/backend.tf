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
