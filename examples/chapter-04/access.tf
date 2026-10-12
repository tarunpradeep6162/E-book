resource "aws_security_group" "admin" {
  name_prefix = "orders-admin-"
  description = "No inbound ports; SSM administration"
  vpc_id      = aws_vpc.lab.id
}
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.admin.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  # Lab baseline: production narrows destinations with endpoints/proxy controls.
}
resource "aws_iam_role" "instance" {
  name_prefix = "orders-ssm-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "instance" {
  role = aws_iam_role.instance.name
}
resource "aws_instance" "admin" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.admin.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  metadata_options {
    http_tokens = "required" # Require IMDSv2 session tokens.
  }
  root_block_device {
    encrypted = true
  }
  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_route.outbound,
    aws_route_table_association.private
  ]
}
output "instance_id" { value = aws_instance.admin.id }
