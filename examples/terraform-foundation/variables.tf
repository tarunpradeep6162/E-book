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
