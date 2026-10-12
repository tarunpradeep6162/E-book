# Chapter 18: Azure as a Second Home: Port the Platform Without Pretending Clouds Match

## Renaming Resources Did Not Port the Network

The engineer replaces `aws_vpc` with an Azure-looking resource name and expects the same subnet, identity, and routing behavior. Terraform rejects the configuration. The next attempt creates AKS but fails because the cluster identity lacks permission on its selected subnet.

Cloud portability is not text substitution. Similar architectural roles have different APIs, identity models, defaults, and operational constraints. **Reuse application contracts where they are stable; implement cloud-specific infrastructure honestly.**

## Map Responsibilities, Not Resource Names

| Responsibility | AWS | Azure |
|---|---|---|
| Network address domain | VPC | Virtual Network |
| Managed Kubernetes | EKS | AKS |
| Image registry | ECR | ACR |
| Resource authorization | IAM | Azure RBAC and Microsoft Entra identities |
| Pod cloud identity | IRSA or EKS Pod Identity | Microsoft Entra Workload ID |
| Terraform backend | S3 | Azure Blob backend |

Microsoft Entra ID is the current name for the directory platform previously called Azure AD. Directory identity, Azure resource authorization, and Kubernetes RBAC are related but distinct layers. Do not assume authenticating to Azure grants access to every AKS namespace.

Use separate Azure roots, provider locks, backend credentials, and subscriptions for environment boundaries. Do not make the Azure apply depend on an AWS state backend that would be unavailable during an AWS outage unless that dependency has an independently tested recovery plan.

## A Deliberate AKS Foundation

This example uses Azure CNI overlay with Cilium for network policy enforcement. Pod address ranges and service ranges must not overlap the VNet or connected networks. Confirm the chosen region, version, and network configuration are supported before deployment.

The example assumes an existing delegated application subnet and an existing user-assigned cluster identity authorized to use it. That keeps network ownership separate. Grant the identity the required network role at the intended scope through a reviewed bootstrap step, not an unrestricted subscription-wide assignment.

### aks.tf

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # Commit lock selection; review upgrades.
    }
  }
}
variable "subscription_id" { type = string }
variable "subnet_id" { type = string }
variable "cluster_identity_id" { type = string }
variable "kubernetes_version" { type = string }
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
resource "azurerm_resource_group" "platform" {
  name     = "orders-platform-lab"
  location = "centralindia"
}
resource "azurerm_kubernetes_cluster" "platform" {
  name                = "orders-aks"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  dns_prefix          = "orders-aks"
  kubernetes_version  = var.kubernetes_version

  private_cluster_enabled   = true
  oidc_issuer_enabled        = true
  workload_identity_enabled = true
  role_based_access_control_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [var.cluster_identity_id]
  }
  default_node_pool {
    name           = "system"
    node_count     = 2
    vm_size        = "Standard_D2s_v5"
    vnet_subnet_id = var.subnet_id
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    pod_cidr            = "10.81.0.0/16"
    service_cidr        = "10.82.0.0/16"
    dns_service_ip      = "10.82.0.10"
  }
}
output "oidc_issuer" {
  value = azurerm_kubernetes_cluster.platform.oidc_issuer_url
}
```

The provider range is not an exact binary selection; the committed lock file establishes that selection, and the deployment baseline must record it. Generate the lock from the actual trusted registry, not by inventing checksums. A future provider upgrade requires a reviewed plan.

A private AKS endpoint needs private DNS and operator connectivity. Test the execution agent's DNS resolution and route to the API before deployment steps. As on AWS, credentials do not create network reachability.

## Separate Cluster and Workload Identities

The cluster's managed identity performs platform operations. The kubelet identity retrieves selected node resources, including registry images where authorized. Application Pods should obtain their own scoped workload identity rather than inherit broad node access.

For a worker identity, create a user-assigned managed identity and federated credential constrained to the AKS issuer and service-account subject:

### worker-identity.tf

```hcl
resource "azurerm_user_assigned_identity" "worker" {
  name                = "orders-worker"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
}
resource "azurerm_federated_identity_credential" "worker" {
  name                = "orders-worker-aks"
  resource_group_name = azurerm_resource_group.platform.name
  parent_id           = azurerm_user_assigned_identity.worker.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.platform.oidc_issuer_url
  subject             = "system:serviceaccount:orders:orders-worker"
}
```

Grant the worker only the required Azure resource role at the intended scope. The federation declaration enables token exchange; it does not automatically grant storage or secret permissions.

The Kubernetes service account needs the managed identity client-ID annotation, and the Pod template needs the workload-identity use label supported by the integration. Use a compatible SDK and verify effective identity. Keep application credential code behind a cloud-specific adapter rather than spreading token assumptions across business logic.

## Registry and Release Contracts

ACR image retrieval requires the correct identity and repository permissions. An image available in ECR is not automatically available in Azure. Copy the approved artifact without rebuilding and verify the resulting registry digest and signature policy.

Registry translation can affect references and supported metadata. Record source and destination identities, preserve provenance, and test image pulls from the secondary cluster while the primary cloud is unreachable.

Keep release values cloud specific: ingress class, load-balancer configuration, secret integration, storage class, identity annotations, and registry location differ. Application ports, HTTP routes, idempotency behavior, and compatible schema contracts can remain stable.

## State and Security Boundaries

Configure Azure remote state using its documented backend identity and locking behavior. Blob leases provide backend coordination; do not assume the S3 lock-object IAM policy applies to Azure. Scope storage access, encryption, versioning, and recovery separately.

Backend state may contain sensitive platform outputs. Restrict who can retrieve cluster credential material, avoid exporting kubeconfig indiscriminately, and use supported Entra authentication instead of broadly sharing administrative credentials.

Use network policies and admission rules consistent with the application's contracts, then prove enforcement on Azure's actual data plane. A YAML policy tested only on AWS has not been operationally verified in AKS.

## Validate Differences Explicitly

Connect through the intended private path and obtain normal user credentials:

```bash
az account show --query '{subscription:id,tenant:tenantId}'
az aks get-credentials --resource-group orders-platform-lab \
  --name orders-aks
kubectl config current-context
kubectl get nodes -o wide
kubectl auth can-i get pods -n orders
```

Check that the selected subscription and tenant match the environment matrix. Run image-pull, DNS, workload-identity, allowed/denied traffic, storage, and graceful-shutdown tests. Compare results with AWS without pretending their implementation details match.

A successful Azure deployment does not prove disaster recovery. The database, secret source, image registry, DNS authority, and release evidence must also be available during a primary-cloud failure. Chapter 21 will define that exercise.

## Upgrade and Cleanup

AKS upgrades, node images, network plugins, and identity integrations have their own compatibility requirements. Record the tested provider, Kubernetes version, CLI, and add-on inventory. Do not derive the Azure release schedule from EKS's version availability.

Before destruction, review node-resource-group ownership and controller-created resources. Retain data and backups under explicit policy, and remove application load balancers through their owner. Keep the recovery cloud's backend independent of the environment being retired.

The result is a second platform with equivalent application behavior and explicit cloud-specific operational contracts. That is a useful multi-cloud capability; a large boolean-heavy abstraction is not required to achieve it.

## Model Azure Egress and Administration Separately

The network profile selects container networking behavior; it does not document every permitted destination. Decide whether outbound traffic uses the supported default path, NAT, or a user-defined inspected route, and configure dependencies consistently with that choice.

For a private cluster, record the private DNS-zone ownership and how connected administrators resolve it. A recovery agent in another network may need different resolver forwarding from the ordinary Azure operator. Test that path while primary AWS services are unavailable.

Subscription permissions can be inherited from management groups or broad role assignments. Review effective authorization, not just the narrow role created for this chapter. A constrained worker identity does not help if the application falls back to a privileged credential embedded in configuration.

If using ACR with repository-scoped permissions or attribute-based access features, choose the registry permission model deliberately and verify the kubelet's actual pull behavior. Do not assume an old AcrPull example covers every registry authorization mode.

Back up the non-secret identity mapping and resource inventory, while keeping token and secret recovery outside Git. Changing a federated credential's subject can break workload authentication even when the managed identity still exists.

Before accepting Azure as the recovery site, prove its control path is independent: operator authentication, private API access, image retrieval, DNS authority, secrets, and database write ownership. A working deployment that relies on a live AWS service for any of those functions needs an explicit exception or redesign.

Verify the recovery operator can resolve the private endpoint from the approved network without using primary-cloud DNS dependencies.

## Key Takeaways

- **Map architectural responsibilities, not API names.**
- **Keep Azure state, subscriptions, and identities independently owned.**
- **Workload federation and resource permissions are separate steps.**
- **Private AKS access requires tested DNS and connectivity.**
- **Copy approved images without rebuilding and verify destination identity.**
- **Test cloud-specific networking, storage, upgrades, and recovery.**

## References

- AKS Workload ID: [Documentation](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)
- Azure CNI overlay: [Documentation](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)
