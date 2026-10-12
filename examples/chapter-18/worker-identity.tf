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
