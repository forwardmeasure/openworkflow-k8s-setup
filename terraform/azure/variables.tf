variable "location" {
  type    = string
  default = "East US"
}

variable "name" {
  type    = string
  default = "openworkflow-dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "resource_group_name" {
  description = "Optional existing naming choice; defaults to <name>-rg. The resource group is created by this stack."
  type        = string
  default     = null
}

variable "vnet_cidr" {
  type    = string
  default = "10.60.0.0/16"
}

variable "aks_subnet_cidr" {
  type    = string
  default = "10.60.0.0/20"
}

variable "postgres_subnet_cidr" {
  type    = string
  default = "10.60.16.0/24"
}

variable "private_endpoints_subnet_cidr" {
  description = "Subnet reserved for private endpoints such as Azure Blob Storage."
  type        = string
  default     = "10.60.17.0/24"
}

variable "pod_cidr" {
  type    = string
  default = "10.64.0.0/14"
}

variable "service_cidr" {
  type    = string
  default = "10.68.0.0/16"
}

variable "api_server_authorized_ip_ranges" {
  description = "Operator CIDRs allowed to reach the AKS API endpoint."
  type        = list(string)

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0
    error_message = "At least one operator CIDR must be supplied."
  }
}

variable "aks_admin_group_object_ids" {
  description = "Microsoft Entra group object IDs granted AKS cluster-administrator access."
  type        = set(string)

  validation {
    condition     = length(var.aks_admin_group_object_ids) > 0
    error_message = "At least one durable AKS administrator group object ID must be supplied."
  }
}

variable "kubernetes_version" {
  description = "Optional AKS Kubernetes version. Null selects the current platform default."
  type        = string
  default     = null
}

variable "system_vm_size" {
  type    = string
  default = "Standard_D4ds_v5"
}

variable "workload_vm_size" {
  type    = string
  default = "Standard_D8ds_v5"
}

variable "geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backup on each PostgreSQL Flexible Server. Availability depends on the selected Azure region."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Apply CanNotDelete management locks to managed Kubernetes, PostgreSQL, and object-storage resources."
  type        = bool
  default     = true
}

variable "databases" {
  description = "Azure PostgreSQL Flexible Servers, migration administrators, and least-privilege runtime roles created later by the database-migration service."
  type = map(object({
    database_name          = string
    administrator_username = string
    runtime_username       = string
    sku_name               = optional(string, "GP_Standard_D2ds_v5")
    storage_mb             = optional(number, 65536)
    high_availability_mode = optional(string, "ZoneRedundant")
  }))
  default = {
    kafka_streams = {
      database_name          = "openworkflow_kafka_streams"
      administrator_username = "openworkflow_kafka_migration"
      runtime_username       = "openworkflow_kafka"
    }
    actor_engine = {
      database_name          = "openworkflow_actor_engine"
      administrator_username = "openworkflow_actor_migration"
      runtime_username       = "openworkflow_actor"
    }
  }

  validation {
    condition = alltrue([
      for database in values(var.databases) : contains(["Disabled", "SameZone", "ZoneRedundant"], database.high_availability_mode)
    ])
    error_message = "high_availability_mode must be Disabled, SameZone, or ZoneRedundant."
  }
}

variable "workload_identities" {
  description = "Azure workload identities to create for Kubernetes service accounts owned by the downstream deployment layer."
  type = map(object({
    namespace                   = string
    service_account             = string
    bucket_keys                 = optional(set(string), [])
    administrator_database_keys = optional(set(string), [])
    runtime_database_keys       = optional(set(string), [])
  }))
  default = {}
}

variable "buckets" {
  description = "Azure Blob containers required by the deployment. No storage account is created unless declared."
  type = map(object({
    name = optional(string)
  }))
  default = {}
}
