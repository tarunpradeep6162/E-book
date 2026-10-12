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
