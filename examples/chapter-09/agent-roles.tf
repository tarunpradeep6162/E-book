variable "account_id" { type = string }
resource "aws_iam_role" "release_agent" {
  name = "orders-release-agent"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "release_agent" {
  role = aws_iam_role.release_agent.name
}
resource "aws_iam_role" "deployment" {
  name                 = "orders-production-deployment"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { AWS = aws_iam_role.release_agent.arn }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "assume_deployment" {
  role = aws_iam_role.release_agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.deployment.arn
    }]
  })
}
