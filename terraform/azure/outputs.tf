output "cluster_name" { value = azurerm_kubernetes_cluster.platform.name }
output "cluster_location" { value = azurerm_resource_group.platform.location }
output "resource_group_name" { value = azurerm_resource_group.platform.name }
output "database_hosts" { value = { for key, value in azurerm_postgresql_flexible_server.platform : key => value.fqdn } }
output "database_port" { value = 5432 }
output "database_names" { value = { for key, value in var.databases : key => value.database_name } }
output "database_usernames" { value = { for key, value in var.databases : key => value.username } }
output "database_passwords" {
  value     = { for key, value in random_password.database : key => value.result }
  sensitive = true
}
output "storage_account_name" { value = try(azurerm_storage_account.platform[0].name, null) }
output "bucket_names" { value = { for key, value in azurerm_storage_container.platform : key => value.name } }
output "kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.platform.name} --name ${azurerm_kubernetes_cluster.platform.name}"
}
