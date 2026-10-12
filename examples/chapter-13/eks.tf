variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "platform_admin_role_arn" { type = string }
variable "kubernetes_version" {
  type = string
  # Supply a currently supported version verified for this region.
}
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.3.0"

  name               = "orders-platform"
  kubernetes_version = var.kubernetes_version
  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids

  endpoint_private_access = true
  endpoint_public_access  = false
  enable_irsa             = true
  authentication_mode     = "API"
  enable_cluster_creator_admin_permissions = false

  # Explicit administrative identity, independent of the original creator.
  access_entries = {
    platform_admin = {
      principal_arn = var.platform_admin_role_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
  addons = {
    vpc-cni = { before_compute = true }
    coredns = {}
    kube-proxy = {}
  }
  eks_managed_node_groups = {
    application = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m6i.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 40
    }
  }
  tags = { Project = "orders", Environment = "lab" }
}
output "cluster_name" { value = module.eks.cluster_name }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
