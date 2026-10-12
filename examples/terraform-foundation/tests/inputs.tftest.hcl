mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/test"
      user_id    = "test"
    }
  }
}
run "accept_valid_contract" {
  command = plan
  variables {
    deployment = {
      account_id  = "123456789012"
      region      = "ap-south-1"
      environment = "dev"
      project     = "orders"
    }
  }
}
run "reject_invalid_contract" {
  command = plan
  variables {
    deployment = {
      account_id  = "wrong-account"
      region      = "unapproved-region"
      environment = "unknown"
      project     = "Bad Name"
    }
  }
  expect_failures = [var.deployment]
}
