output "cluster_name" { value = azurerm_kubernetes_cluster.platform.name }
output "cluster_location" { value = azurerm_resource_group.platform.location }
output "cluster_endpoint" {
  value     = azurerm_kubernetes_cluster.platform.fqdn
  sensitive = true
}
output "resource_group_name" { value = azurerm_resource_group.platform.name }
output "cloud_subscription_id" { value = data.azurerm_client_config.current.subscription_id }
output "cloud_tenant_id" { value = data.azurerm_client_config.current.tenant_id }
output "network_id" { value = azurerm_virtual_network.platform.id }
output "cluster_subnet_ids" { value = [azurerm_subnet.aks.id] }
output "database_subnet_ids" { value = [azurerm_subnet.postgres.id] }
output "database_network_cidrs" { value = [var.postgres_subnet_cidr] }
output "workload_identity_issuer" { value = azurerm_kubernetes_cluster.platform.oidc_issuer_url }
output "database_hosts" { value = { for key, value in azurerm_postgresql_flexible_server.platform : key => value.fqdn } }
output "database_port" { value = 5432 }
output "database_names" { value = { for key, value in var.databases : key => value.database_name } }
output "database_ssl_mode" { value = "verify-full" }
output "database_role_provisioning_required" { value = true }
output "database_administrator_usernames" {
  value = { for key, value in var.databases : key => value.administrator_username }
}
output "database_administrator_secret_ids" {
  value = { for key, value in azurerm_key_vault_secret.database_administrator : key => value.id }
}
output "database_runtime_usernames" {
  value = { for key, value in var.databases : key => value.runtime_username }
}
output "database_runtime_secret_ids" {
  value = { for key, value in azurerm_key_vault_secret.database_runtime : key => value.id }
}
output "storage_account_name" { value = try(azurerm_storage_account.platform[0].name, null) }
output "bucket_names" { value = { for key, value in azurerm_storage_container.platform : key => value.name } }
output "bucket_ids" { value = { for key, value in azurerm_storage_container.platform : key => value.resource_manager_id } }
output "bucket_uris" {
  value = {
    for key, value in azurerm_storage_container.platform : key => "https://${azurerm_storage_account.platform[0].name}.blob.core.windows.net/${value.name}"
  }
}
output "workload_identity_bindings" {
  value = {
    for key, value in var.workload_identities : key => {
      namespace                   = value.namespace
      kubernetes_service_account  = value.service_account
      cloud_principal             = azurerm_user_assigned_identity.workload[key].principal_id
      client_id                   = azurerm_user_assigned_identity.workload[key].client_id
      service_account_annotation  = "azure.workload.identity/client-id=${azurerm_user_assigned_identity.workload[key].client_id}"
      bucket_keys                 = sort(tolist(value.bucket_keys))
      administrator_database_keys = sort(tolist(value.administrator_database_keys))
      runtime_database_keys       = sort(tolist(value.runtime_database_keys))
    }
  }
}
output "kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.platform.name} --name ${azurerm_kubernetes_cluster.platform.name}"
}

output "deployment_handoff" {
  sensitive = true
  value = {
    cloud_provider = "azure"
    cloud_scope    = data.azurerm_client_config.current.subscription_id
    cluster = {
      name                     = azurerm_kubernetes_cluster.platform.name
      location                 = azurerm_resource_group.platform.location
      endpoint                 = azurerm_kubernetes_cluster.platform.fqdn
      network_id               = azurerm_virtual_network.platform.id
      subnet_ids               = [azurerm_subnet.aks.id]
      workload_identity_issuer = azurerm_kubernetes_cluster.platform.oidc_issuer_url
    }
    databases = {
      for key, database in var.databases : key => {
        host                       = azurerm_postgresql_flexible_server.platform[key].fqdn
        port                       = 5432
        name                       = database.database_name
        ssl_mode                   = "verify-full"
        administrator_username     = database.administrator_username
        administrator_secret_id    = azurerm_key_vault_secret.database_administrator[key].id
        runtime_username           = database.runtime_username
        runtime_secret_id          = azurerm_key_vault_secret.database_runtime[key].id
        role_provisioning_required = true
      }
    }
    object_storage = {
      for key, container in azurerm_storage_container.platform : key => {
        name = container.name
        id   = container.resource_manager_id
        uri  = "https://${azurerm_storage_account.platform[0].name}.blob.core.windows.net/${container.name}"
      }
    }
    workload_identities = {
      for key, identity in var.workload_identities : key => {
        namespace                  = identity.namespace
        kubernetes_service_account = identity.service_account
        cloud_principal            = azurerm_user_assigned_identity.workload[key].principal_id
        client_id                  = azurerm_user_assigned_identity.workload[key].client_id
        service_account_annotation = "azure.workload.identity/client-id=${azurerm_user_assigned_identity.workload[key].client_id}"
      }
    }
  }
}
