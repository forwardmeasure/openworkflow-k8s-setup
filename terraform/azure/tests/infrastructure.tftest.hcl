mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      client_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
      tenant_id       = "00000000-0000-0000-0000-000000000004"
    }
  }

  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.Network/virtualNetworks/openworkflow-test-vnet"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.Network/virtualNetworks/openworkflow-test-vnet/subnets/test"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.ContainerService/managedClusters/openworkflow-test"
      fqdn            = "openworkflow-test.example.azmk8s.io"
      oidc_issuer_url = "https://example.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000004/"
    }
  }

  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/openworkflow-test"
      fqdn = "openworkflow-test.postgres.database.azure.com"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.KeyVault/vaults/openworkflowtest"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/openworkflow-test"
      client_id    = "00000000-0000-0000-0000-000000000006"
      principal_id = "00000000-0000-0000-0000-000000000007"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.Storage/storageAccounts/openworkflowtest"
    }
  }

  mock_resource "azurerm_storage_container" {
    defaults = {
      resource_manager_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.Storage/storageAccounts/openworkflowtest/blobServices/default/containers/backups"
    }
  }

  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/openworkflow-test-rg/providers/Microsoft.Network/privateDnsZones/privatelink.example.com"
    }
  }
}

mock_provider "random" {}

run "production_contract" {
  command = plan

  variables {
    name                            = "openworkflow-test"
    api_server_authorized_ip_ranges = ["203.0.113.10/32"]
    aks_admin_group_object_ids      = ["00000000-0000-0000-0000-000000000005"]
    buckets = {
      backups = {}
    }
    workload_identities = {
      runtime = {
        namespace             = "openworkflow"
        service_account       = "openworkflow-runtime"
        bucket_keys           = ["backups"]
        runtime_database_keys = ["kafka_streams"]
      }
      migrations = {
        namespace                   = "openworkflow"
        service_account             = "openworkflow-database-migration"
        administrator_database_keys = ["kafka_streams", "actor_engine"]
        runtime_database_keys       = ["kafka_streams", "actor_engine"]
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.platform.local_account_disabled
    error_message = "The production contract must disable AKS local accounts."
  }

  assert {
    condition = alltrue([
      for database in azurerm_postgresql_flexible_server.platform : database.high_availability[0].mode == "ZoneRedundant"
    ])
    error_message = "The production contract must enable zone-redundant Azure PostgreSQL."
  }

  assert {
    condition     = output.database_role_provisioning_required
    error_message = "The handoff must require creation of least-privilege runtime roles."
  }
}
