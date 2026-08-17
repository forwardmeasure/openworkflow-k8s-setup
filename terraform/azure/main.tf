locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name}-rg")
  dns_service_ip      = cidrhost(var.service_cidr, 10)
}

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

resource "azurerm_kubernetes_cluster" "platform" {
  name                = var.name
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = false
  role_based_access_control_enabled = true

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
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
  length   = 32
  special  = false
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

  administrator_login          = each.value.username
  administrator_password       = random_password.database[each.key].result
  sku_name                     = each.value.sku_name
  storage_mb                   = each.value.storage_mb
  backup_retention_days        = 14
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

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
  public_network_access_enabled   = true
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
