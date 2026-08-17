locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name}-rg")
  dns_service_ip      = cidrhost(var.service_cidr, 10)
  workload_bucket_bindings = {
    for binding in flatten([
      for identity_key, identity in var.workload_identities : [
        for bucket_key in identity.bucket_keys : {
          key          = "${identity_key}:${bucket_key}"
          identity_key = identity_key
          bucket_key   = bucket_key
        }
      ]
    ]) : binding.key => binding
  }
  workload_administrator_secret_bindings = {
    for binding in flatten([
      for identity_key, identity in var.workload_identities : [
        for database_key in identity.administrator_database_keys : {
          key          = "${identity_key}:${database_key}"
          identity_key = identity_key
          database_key = database_key
        }
      ]
    ]) : binding.key => binding
  }
  workload_runtime_secret_bindings = {
    for binding in flatten([
      for identity_key, identity in var.workload_identities : [
        for database_key in identity.runtime_database_keys : {
          key          = "${identity_key}:${database_key}"
          identity_key = identity_key
          database_key = database_key
        }
      ]
    ]) : binding.key => binding
  }
}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "platform" {
  name     = local.resource_group_name
  location = var.location
  tags     = { Project = "openworkflow", ManagedBy = "opentofu" }
}

resource "azurerm_virtual_network" "platform" {
  name                = "${var.name}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
}

resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = [var.aks_subnet_cidr]
  service_endpoints    = ["Microsoft.KeyVault"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = [var.postgres_subnet_cidr]

  delegation {
    name = "postgres-flexible-server"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = [var.private_endpoints_subnet_cidr]
}

resource "azurerm_kubernetes_cluster" "platform" {
  name                = var.name
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = true
  role_based_access_control_enabled = true

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  azure_active_directory_role_based_access_control {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = sort(tolist(var.aks_admin_group_object_ids))
    azure_rbac_enabled     = true
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    vnet_subnet_id               = azurerm_subnet.aks.id
    auto_scaling_enabled         = true
    min_count                    = 3
    max_count                    = 6
    node_count                   = 3
    only_critical_addons_enabled = true
    zones                        = ["1", "2", "3"]
    node_labels                  = { "openworkflow.io/pool" = "system" }
    os_disk_type                 = "Managed"
    os_disk_size_gb              = 100
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = local.dns_service_ip
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "05:00"
    utc_offset  = "+00:00"
  }

  tags = { Project = "openworkflow", ManagedBy = "opentofu" }
}

resource "azurerm_kubernetes_cluster_node_pool" "workloads" {
  name                  = "workloads"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.platform.id
  vm_size               = var.workload_vm_size
  vnet_subnet_id        = azurerm_subnet.aks.id
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = 3
  max_count             = 9
  node_count            = 3
  zones                 = ["1", "2", "3"]
  node_labels           = { "openworkflow.io/pool" = "workloads" }
  os_disk_type          = "Managed"
  os_disk_size_gb       = 200
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.name}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.platform.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.name}-postgres"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.platform.id
  resource_group_name   = azurerm_resource_group.platform.name
}

resource "random_password" "database" {
  for_each = var.databases
  length   = 40
  special  = false
}

resource "random_password" "database_runtime" {
  for_each = var.databases
  length   = 40
  special  = false
}

resource "azurerm_key_vault" "database_administrator" {
  for_each = var.databases

  name                       = substr("${replace(var.name, "-", "")}${substr(sha256(each.key), 0, 6)}a${random_string.suffix.result}", 0, 24)
  location                   = azurerm_resource_group.platform.location
  resource_group_name        = azurerm_resource_group.platform.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.api_server_authorized_ip_ranges
    virtual_network_subnet_ids = [azurerm_subnet.aks.id]
  }
}

resource "azurerm_key_vault_access_policy" "database_administrator_operator" {
  for_each = var.databases

  key_vault_id = azurerm_key_vault.database_administrator[each.key].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "Set", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_secret" "database_administrator" {
  for_each = var.databases

  name         = "password"
  value        = random_password.database[each.key].result
  key_vault_id = azurerm_key_vault.database_administrator[each.key].id

  depends_on = [azurerm_key_vault_access_policy.database_administrator_operator]
}

resource "azurerm_key_vault" "database_runtime" {
  for_each = var.databases

  name                       = substr("${replace(var.name, "-", "")}${substr(sha256(each.key), 0, 6)}r${random_string.suffix.result}", 0, 24)
  location                   = azurerm_resource_group.platform.location
  resource_group_name        = azurerm_resource_group.platform.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.api_server_authorized_ip_ranges
    virtual_network_subnet_ids = [azurerm_subnet.aks.id]
  }
}

resource "azurerm_key_vault_access_policy" "database_runtime_operator" {
  for_each = var.databases

  key_vault_id = azurerm_key_vault.database_runtime[each.key].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "Set", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_secret" "database_runtime" {
  for_each = var.databases

  name         = "password"
  value        = random_password.database_runtime[each.key].result
  key_vault_id = azurerm_key_vault.database_runtime[each.key].id

  depends_on = [azurerm_key_vault_access_policy.database_runtime_operator]
}

resource "azurerm_postgresql_flexible_server" "platform" {
  for_each = var.databases

  name                          = substr("${var.name}-${replace(each.key, "_", "-")}-${random_string.suffix.result}", 0, 63)
  resource_group_name           = azurerm_resource_group.platform.name
  location                      = azurerm_resource_group.platform.location
  version                       = "17"
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  administrator_login          = each.value.administrator_username
  administrator_password       = random_password.database[each.key].result
  sku_name                     = each.value.sku_name
  storage_mb                   = each.value.storage_mb
  backup_retention_days        = 14
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  dynamic "high_availability" {
    for_each = each.value.high_availability_mode == "Disabled" ? [] : [each.value.high_availability_mode]
    content {
      mode = high_availability.value
    }
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "platform" {
  for_each  = var.databases
  name      = each.value.database_name
  server_id = azurerm_postgresql_flexible_server.platform[each.key].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_storage_account" "platform" {
  count = length(var.buckets) > 0 ? 1 : 0

  name                            = substr("${replace(var.name, "-", "")}ow${random_string.suffix.result}", 0, 24)
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
  tags = { Project = "openworkflow", ManagedBy = "opentofu" }
}

resource "azurerm_storage_container" "platform" {
  for_each              = var.buckets
  name                  = coalesce(each.value.name, replace(each.key, "_", "-"))
  storage_account_id    = azurerm_storage_account.platform[0].id
  container_access_type = "private"
}

resource "azurerm_private_dns_zone" "blob" {
  count = length(var.buckets) > 0 ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.platform.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count = length(var.buckets) > 0 ? 1 : 0

  name                  = "${var.name}-blob"
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.platform.id
  resource_group_name   = azurerm_resource_group.platform.name
}

resource "azurerm_private_endpoint" "blob" {
  count = length(var.buckets) > 0 ? 1 : 0

  name                = "${var.name}-blob"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.name}-blob"
    private_connection_resource_id = azurerm_storage_account.platform[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each = var.workload_identities

  name                = substr("${var.name}-${replace(each.key, "_", "-")}", 0, 128)
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
}

resource "azurerm_federated_identity_credential" "workload" {
  for_each = var.workload_identities

  name                      = substr("${var.name}-${replace(each.key, "_", "-")}", 0, 120)
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.platform.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

resource "azurerm_role_assignment" "workload_bucket" {
  for_each = local.workload_bucket_bindings

  scope                = azurerm_storage_container.platform[each.value.bucket_key].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workload[each.value.identity_key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_key_vault_access_policy" "workload_database_administrator" {
  for_each = local.workload_administrator_secret_bindings

  key_vault_id = azurerm_key_vault.database_administrator[each.value.database_key].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.workload[each.value.identity_key].principal_id

  secret_permissions = ["Get"]
}

resource "azurerm_key_vault_access_policy" "workload_database_runtime" {
  for_each = local.workload_runtime_secret_bindings

  key_vault_id = azurerm_key_vault.database_runtime[each.value.database_key].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.workload[each.value.identity_key].principal_id

  secret_permissions = ["Get"]
}

resource "azurerm_management_lock" "kubernetes" {
  count = var.deletion_protection ? 1 : 0

  name       = "${var.name}-kubernetes-delete-protection"
  scope      = azurerm_kubernetes_cluster.platform.id
  lock_level = "CanNotDelete"
  notes      = "Disable deletion_protection and apply before destroying this cluster."
}

resource "azurerm_management_lock" "database" {
  for_each = var.deletion_protection ? azurerm_postgresql_flexible_server.platform : {}

  name       = "${var.name}-${each.key}-database-delete-protection"
  scope      = each.value.id
  lock_level = "CanNotDelete"
  notes      = "Disable deletion_protection and apply before destroying this database server."
}

resource "azurerm_management_lock" "storage" {
  count = var.deletion_protection && length(var.buckets) > 0 ? 1 : 0

  name       = "${var.name}-storage-delete-protection"
  scope      = azurerm_storage_account.platform[0].id
  lock_level = "CanNotDelete"
  notes      = "Disable deletion_protection and apply before destroying this storage account."
}

resource "azurerm_management_lock" "database_administrator_secret" {
  for_each = var.deletion_protection ? azurerm_key_vault.database_administrator : {}

  name       = "${var.name}-${each.key}-administrator-secret-delete-protection"
  scope      = each.value.id
  lock_level = "CanNotDelete"
  notes      = "Disable deletion_protection and apply before destroying this credential vault."
}

resource "azurerm_management_lock" "database_runtime_secret" {
  for_each = var.deletion_protection ? azurerm_key_vault.database_runtime : {}

  name       = "${var.name}-${each.key}-runtime-secret-delete-protection"
  scope      = each.value.id
  lock_level = "CanNotDelete"
  notes      = "Disable deletion_protection and apply before destroying this credential vault."
}

check "database_names_are_unique" {
  assert {
    condition     = length(distinct([for database in values(var.databases) : database.database_name])) == length(var.databases)
    error_message = "Each logical database must have a unique PostgreSQL database name."
  }
}

check "database_runtime_users_are_unique" {
  assert {
    condition     = length(distinct([for database in values(var.databases) : database.runtime_username])) == length(var.databases)
    error_message = "Each logical database must have a unique runtime username."
  }
}

check "workload_bucket_keys_exist" {
  assert {
    condition = alltrue(flatten([
      for identity in values(var.workload_identities) : [
        for bucket_key in identity.bucket_keys : contains(keys(var.buckets), bucket_key)
      ]
    ]))
    error_message = "Every workload identity bucket key must identify a declared bucket."
  }
}

check "workload_database_keys_exist" {
  assert {
    condition = alltrue(flatten([
      for identity in values(var.workload_identities) : [
        for database_key in setunion(identity.administrator_database_keys, identity.runtime_database_keys) : contains(keys(var.databases), database_key)
      ]
    ]))
    error_message = "Every workload identity database key must identify a declared database."
  }
}
