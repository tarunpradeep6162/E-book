variable "vpc_id" { type = string }
variable "private_route_table_ids" { type = set(string) }
variable "azure_gateway_public_ip" { type = string }
variable "azure_network_cidr" {
  type    = string
  default = "10.80.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.azure_network_cidr))
    error_message = "Supply a valid IPv4 Azure network CIDR."
  }
}
resource "aws_vpn_gateway" "aws" {
  vpc_id = var.vpc_id
  tags = { Name = "orders-cross-cloud" }
}
resource "aws_customer_gateway" "azure" {
  bgp_asn    = 65020 # Required API field; routing here remains static.
  ip_address = var.azure_gateway_public_ip
  type       = "ipsec.1"
}
resource "aws_vpn_connection" "azure" {
  vpn_gateway_id      = aws_vpn_gateway.aws.id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = true
  # Generated tunnel keys are sensitive outputs/state; do not log them.
}
resource "aws_vpn_connection_route" "azure" {
  destination_cidr_block = var.azure_network_cidr
  vpn_connection_id     = aws_vpn_connection.azure.id
}
resource "aws_route" "azure" {
  for_each               = var.private_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = var.azure_network_cidr
  gateway_id             = aws_vpn_gateway.aws.id
}
