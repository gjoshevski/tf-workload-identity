output "resource_group_name" {
  value = azurerm_resource_group.default.name
}

output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.default.name
}

output "oidc_issuer_url" {
  value =azurerm_kubernetes_cluster.default.oidc_issuer_url
}

output "azuread_application_id" {
  value = azuread_application.directory_role_app.application_id
  
}

# output "login_server" {
#   value = azurerm_container_registry.acr.login_server
# }

# output "admin_username" {
#   value = azurerm_container_registry.acr.admin_username
# }

#  output "admin_password" {
#   value = nonsensitive(azurerm_container_registry.acr.admin_password)
# }

# output "client_certificate" {
#   value = azurerm_kubernetes_cluster.default.kube_config.0.client_certificate
# }

# output "kube_config" {
#   value = azurerm_kubernetes_cluster.default.kube_config_raw
# }

# output "cluster_username" {
#   value = azurerm_kubernetes_cluster.default.kube_config.0.username
# }

# output "cluster_password" {
#   value = azurerm_kubernetes_cluster.default.kube_config.0.password
# }