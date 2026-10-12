resource "aws_vpc" "this" {
  cidr_block           = var.network.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = var.network.name }
}
resource "aws_subnet" "this" {
  # Stable keys express topology, never mutable display labels.
  for_each = var.network.subnets
  vpc_id   = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  map_public_ip_on_launch = false
  tags = { Name = "${var.network.name}-${each.key}" }
}
