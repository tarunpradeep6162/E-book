# Chapter 4: AWS from Zero: Provision a Network You Can Explain

## The Database That Answered the Internet

The startup's order database disappears during lunch. An attacker connected to a PostgreSQL listener exposed through a public address, guessed an administrative password, and deleted the tables. A note demands payment for a recovery key that does not exist.

The database sat in a public subnet because the engineer copied the application server's launch settings. Its security group allowed port 5432 from everywhere to simplify testing. No restore exercise had verified the backup.

A public subnet alone does not expose a database: public addressing, routing, permissive controls, and a listening service complete the path. That distinction matters because deleting an Internet Gateway route will not fix stolen credentials or recover data. **Prevent exposure at multiple boundaries, and recover from independently protected backups.**

## A Route Is a Decision

A VPC establishes a private addressing domain. A subnet occupies part of that address space in one Availability Zone. A route table tells traffic where to go; it does not authenticate the sender or filter the application protocol.

A public subnet has a route to an Internet Gateway. An IPv4 instance also needs a public address and appropriate security controls for direct internet communication. A private subnet does not have that direct route. It can still reach external destinations through a NAT gateway or service endpoints.

NAT supports outbound connections and their return traffic. It is not a firewall policy engine, does not inspect application content, and does not make unrestricted egress safe. Security groups, proxies, endpoint policies, and optional inspected routing constrain destinations and identities.

Security groups are stateful. Return traffic for allowed connections is handled without a corresponding broad inbound rule. Network ACLs are stateless subnet controls; if used, their return-port rules must be understood. Start with clearly owned security groups rather than adding complicated ACLs without a test plan.

## Lab and Production Are Different Architectures

The lab below creates one public and one private subnet in a selected AZ. One NAT gateway lets a private EC2 instance reach Systems Manager and approved HTTPS services. There is no public IP on that instance and no inbound SSH rule.

Production commonly uses at least two AZs, separate application and database subnets, and an application entry point across AZs. A NAT gateway per AZ avoids making outbound access depend on another AZ and can reduce cross-AZ traffic, but increases recurring charges. Do not copy that cost into a weekend lab without a reason.

SSM Session Manager needs an instance profile, the SSM agent, service connectivity, and operator authorization. An IAM policy alone does not create the network path. VPC interface endpoints can replace selected internet paths, but require endpoint security groups, DNS configuration, and any additional endpoints needed for logging, image retrieval, or package sources.

**No ingress does not mean no administration.** It means administration uses an authenticated, audited control path rather than an exposed SSH listener.

## Provision the Lab Root

Use Chapter 2's pinned AWS provider and Chapter 3's independently bootstrapped backend. This example is a separate root, not another file inside the backend bootstrap. Choose a currently supported AMI with SSM Agent installed, and verify the instance architecture matches it.

### network.tf

```hcl
variable "ami_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "Use a reviewed regional AMI ID."
  }
}
variable "availability_zone" {
  type = string
  # Supply an AZ in the provider's region; discovery is not an architecture.
}
resource "aws_vpc" "lab" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "orders-lab" }
}
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.40.0.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
}
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.40.10.0/24"
  availability_zone = var.availability_zone
}
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
}
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  domain = "vpc"
}
resource "aws_nat_gateway" "lab" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  # The subnet reference does not express internet-route readiness.
  depends_on = [aws_route.internet]
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id
}
resource "aws_route" "outbound" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.lab.id
}
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
```

Explicit subnet associations prevent surprises from the VPC's main route table. Reserve address ranges for future AZs, endpoints, and containers. Avoid choosing the same range for another cloud; Chapter 20 will make overlapping ranges an expensive mistake.

### access.tf

```hcl
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
```

AWS-provided DNS resolution has special behavior; a missing arbitrary UDP-53 internet rule is not permission to assume every DNS design works. Test resolution from the actual instance. If using your own resolver, explicitly allow that resolver and document forwarding paths.

## Verify Behavior, Not Just Objects

Run formatting, initialization, validation, and a reviewed saved plan before applying. IAM propagation can be eventual; do not hide persistent authorization errors behind unlimited retries. Verify which instance role was actually attached.

```bash
terraform output -raw instance_id
aws ssm describe-instance-information
# Replace the ID with this root's output.
aws ssm start-session --target i-REPLACE
```

An operator needs separate Session Manager permissions. The instance role does not authorize your human identity to start sessions. Restrict operator access to tagged lab instances, require MFA through your identity provider, and configure session audit destinations. Port forwarding has different logging capabilities from an interactive shell; review it as a separate access mode.

Inside the session, verify DNS resolution and HTTPS reachability. Confirm the instance has no public IPv4 address and the security group has no inbound rules. Check the private route table points to the intended NAT, not directly to the Internet Gateway.

For the future database, authorize port 5432 from the application security group, not from the entire VPC range. Put administrative tooling behind a separate identity and network boundary. A compromised application must not inherit database administrator privileges merely because its packets originate inside a VPC.

Record the cost of the NAT gateway, allocated public IPv4 address, instance, EBS storage, and logs. Stop or destroy disposable lab resources after verification; stopping EC2 does not stop NAT or retained-storage charges. Inspect the destroy plan and never combine the lab root with protected state infrastructure.

## Diagnose the First Broken Hop

When SSM does not register the instance, divide the investigation by boundary. First confirm the instance is running with the expected AMI and role. Then check the agent process and its logs through an approved out-of-band lab access method. Next inspect DNS, outbound route, NAT health, and endpoint connectivity. Finally review service authorization.

Do not add inbound SSH from the internet as the default diagnostic action. That creates another exposure path without identifying the original failure. If an emergency access mechanism is required, predefine its restricted source, short lifetime, approval owner, and removal verification.

For application connectivity, write a hop table: caller security group, source subnet route, destination subnet route, destination security group, service listener, TLS identity, and database role. A timeout suggests a different boundary from an authentication rejection. Preserve that distinction in alerts and runbooks.

Use VPC Flow Logs where appropriate to inspect accepted or rejected flows, understanding that they are metadata rather than full packet captures. Their delivery and retention have cost and privacy implications. An entry showing accepted packets does not prove PostgreSQL accepted the transaction.

The lab acceptance record should contain both a successful administrative session and evidence that unsolicited inbound access remains unavailable. This makes the security claim measurable instead of relying on a diagram.

## Key Takeaways

- **Routing, addressing, and authorization are separate controls.**
- **A private subnet needs an intentional outbound and administrative path.**
- **SSM requires identity, agent health, and connectivity.**
- **Keep databases private and restrict callers by workload identity and security group.**
- **Label single-AZ labs honestly; design multi-AZ production deliberately.**
- **Test both permitted and denied paths, then clean up chargeable resources.**

## References

- AWS VPC route tables: [Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html)
- Session Manager prerequisites: [Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html)
