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
