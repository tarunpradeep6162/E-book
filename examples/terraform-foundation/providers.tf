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
