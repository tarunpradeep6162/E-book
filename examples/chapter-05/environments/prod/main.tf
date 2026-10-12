module "network" {
  source = "../../modules/network"
  network = {
    name = "orders-prod"
    cidr = "10.50.0.0/16"
    subnets = {
      app_a = { cidr = "10.50.10.0/24", az = "ap-south-1a" }
      app_b = { cidr = "10.50.20.0/24", az = "ap-south-1b" }
    }
  }
}
output "vpc_id" { value = module.network.vpc_id }
