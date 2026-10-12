module "network" {
  source = "../../modules/network"
  network = {
    name = "orders-dev"
    cidr = "10.40.0.0/16"
    subnets = {
      app_a = { cidr = "10.40.10.0/24", az = "ap-south-1a" }
    }
  }
}
output "vpc_id" { value = module.network.vpc_id }
