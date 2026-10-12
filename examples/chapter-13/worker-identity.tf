locals {
  issuer = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}
resource "aws_iam_role" "worker" {
  name = "orders-worker-irsa"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.issuer}:sub" = "system:serviceaccount:orders:orders-worker"
          "${local.issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
output "worker_role_arn" { value = aws_iam_role.worker.arn }
