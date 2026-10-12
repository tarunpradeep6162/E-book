# Chapter 13: AWS Kubernetes: Build an EKS Platform with Terraform

## The Cluster Only Its Creator Understood

The engineer who created EKS through the console leaves the company. Months later, nodes are full and a control-plane upgrade is required. Nobody knows which IAM roles, subnet tags, add-ons, or access entries were changed manually.

The platform team can see the cluster but cannot reliably reproduce or administer it. A managed control plane reduced server maintenance; it did not remove ownership decisions.

**EKS manages selected control-plane responsibilities. You still own identity, worker capacity, networking, upgrades, application state, and recovery.** Record those decisions in code and test them before the original administrator becomes a dependency.

## Split Cloud Provisioning from Workload Deployment

Terraform owns the EKS cluster, node groups, IAM relationships, and surrounding AWS resources. Kubernetes manifests own application workloads. A separate platform configuration layer owns reviewed add-ons and cluster policies.

Avoid a single apply that creates a private cluster and immediately tries to deploy every Kubernetes object using a provider that cannot yet authenticate or reach the endpoint. Separate execution phases and identities make bootstrap failures understandable.

Use the multi-AZ network contract from earlier chapters. Private node subnets need outbound paths to required services or configured endpoints. Nodes must retrieve images, communicate with the control plane, and use identity services. Do not assume a private endpoint makes all required traffic private automatically.

## The Module Is Community Maintained

The widely used `terraform-aws-modules/eks/aws` module is community maintained, not an AWS-official Terraform module. The AWS provider supplies the underlying managed resources. Use an exact module version and review its inputs rather than mixing examples from different major releases.

This example targets module 21.3.0, whose inputs include `name`, `kubernetes_version`, and `addons`. Older examples using `cluster_name` or `cluster_addons` should not be pasted into this configuration unchanged.

### eks.tf

```hcl
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
```

Keep the approved AWS provider pin and remote backend in this root. The subnet list must span appropriate AZs and contain enough IP capacity. This configuration is a foundation, not a claim that every production control is complete.

Review add-on versions explicitly before adoption. Omitting versions lets selection behavior depend on module and API defaults. For a reproducible platform release, record compatible tested versions, node-image selection, and the control-plane version in the release inventory.

The private endpoint requires an agent or operator with network reachability through the VPC or approved connected network. A laptop's AWS credentials do not provide that path. Plan how emergency administrators authenticate and connect before disabling public access.

## IRSA Connects a Specific Service Account

Enabling an OIDC provider does not grant every Pod AWS permissions. IRSA maps a projected service-account token to an IAM role through issuer, subject, and audience conditions.

The example below trusts only `orders/orders-worker`. Give its role a separate policy granting the intended object-store operations; do not attach broad storage administration.

### worker-identity.tf

```hcl
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
```

### worker-service-account.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-worker
  namespace: orders
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/orders-worker-irsa
```

Replace the ARN with the output and set the worker Pod's `serviceAccountName`. Compatible SDKs must use the projected identity correctly. A Pod configured with `automountServiceAccountToken: false` needs deliberate review of the IRSA webhook's token projection rather than assuming the Chapter 12 non-cloud fixture settings apply unchanged.

EKS Pod Identity is another supported approach with different prerequisites and associations. Do not mix mechanisms accidentally. Record which identity path the workload uses and test its effective AWS identity from an authorized diagnostic workload.

## Access Is Not One Permission

AWS authorization to call `DescribeCluster`, Kubernetes authentication, Kubernetes authorization, and endpoint connectivity are separate requirements. `aws eks update-kubeconfig` writes connection configuration; it does not grant cluster administrator rights.

```bash
aws eks update-kubeconfig --region ap-south-1 \
  --name orders-platform
kubectl config current-context
kubectl auth can-i get pods -n orders
kubectl get nodes -o wide
kubectl -n kube-system get pods
```

Use the explicit approved role and private connectivity. Inspect node readiness, DNS, CNI health, available IPs, and image retrieval before deploying the API. A healthy control plane with broken node networking does not constitute a working platform.

## Upgrades Are Platform Releases

Rehearse upgrades with representative workloads and admission policies. Check deprecated APIs, add-on compatibility, node AMIs, client versions, and disruption budgets. A control-plane upgrade and worker replacement are related but distinct operations.

Terraform's desired node count can conflict with an autoscaler that owns runtime capacity. Decide which controller owns which fields and document ignored changes carefully. Do not add broad `ignore_changes` rules merely to suppress unexplained drift.

Drain nodes only after reviewing capacity and PDB behavior. A two-node pool may not have enough room for a surge workload during maintenance. Prove scheduling headroom and storage placement rather than relying on minimum node count alone.

## Recovery and Cleanup

Cloud state records platform ownership; it does not contain PostgreSQL records, Kubernetes Secret recovery material, or every dynamically created volume. Inventory add-on-created resources and their owner before dismantling the cluster.

Remove application load balancers and disposable workloads through their owning controllers before destroying cloud networking. Retain protected database volumes according to policy. Destroying the EKS cluster first can orphan controller-managed AWS resources and leave chargeable infrastructure without its reconciliation engine.

Test a node-group replacement, lost administrative session, denied workload identity, and failed image pull in the lab. Record whether existing orders remain durable and whether diagnostics identify the correct failed boundary.

A reproducible EKS platform is one another engineer can administer and upgrade using approved identities and documented connectivity. It is not simply a green Terraform apply.

## Version the Entire Platform Envelope

An EKS platform release includes more than the cluster version. Record the Terraform CLI, AWS provider, EKS module, CNI, DNS, proxy, CSI components, node image, admission configuration, and diagnostic clients. Compatibility exists across that envelope, not between two version numbers alone.

For add-ons, select the tested release supported by the target cluster version and region. Observe existing configuration before upgrading so an update does not reset intentional settings. Keep identity changes and binary upgrades separately reviewable where possible.

Node bootstrap can fail while the control plane remains healthy. Inspect instance launch, security groups, outbound paths, instance roles, bootstrap logs, and cluster authentication. Do not create public nodes simply to make registration work without understanding which private dependency failed.

Test subnet exhaustion using a capacity model rather than allocating addresses until production breaks. Container networking can consume addresses beyond the number of nodes. Include surge nodes, endpoint interfaces, maintenance, and future workloads in the subnet budget.

Account for capacity during recovery. If the selected instance family is unavailable in one AZ, a multi-AZ design may still need alternate compatible instance types and correct architecture selection. A list of types should reflect tested workload compatibility rather than arbitrary availability guesses.

Finally, validate the emergency administration role from its actual access path and record that exercise. An explicit access entry is useful only if the identity can authenticate, reach the endpoint, and perform the documented repair actions without inheriting unrelated platform privileges.

This inventory becomes the baseline for upgrades and incident comparison: when behavior changes, the team can identify which part of the operating envelope changed.

Test a denied administrative action as well as a permitted read, confirming the chosen identity respects the intended namespace and cluster boundaries.

## Key Takeaways

- **Managed control planes still require explicit platform ownership.**
- **Pin the community module and use its version-specific inputs.**
- **Separate cloud bootstrap from cluster configuration.**
- **IRSA trusts a constrained issuer, subject, and audience.**
- **Private endpoints require a tested administration path.**
- **Upgrade and cleanup plans must include add-ons and persistent resources.**

## References

- EKS module 21.3.0: [Documentation](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/21.3.0)
- IRSA: [Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
