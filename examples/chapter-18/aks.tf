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
