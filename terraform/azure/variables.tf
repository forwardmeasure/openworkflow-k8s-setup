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

variable "databases" {
  description = "Azure PostgreSQL Flexible Servers and initial databases. One server per runtime gives each database its own control-plane-managed login."
  type = map(object({
    database_name = string
    username      = string
    sku_name      = optional(string, "B_Standard_D2ds_v5")
    storage_mb    = optional(number, 65536)
  }))
  default = {
    kafka_streams = {
      database_name = "openworkflow_kafka_streams"
      username      = "openworkflow_kafka"
    }
    actor_engine = {
      database_name = "openworkflow_actor_engine"
      username      = "openworkflow_actor"
    }
  }
}

variable "buckets" {
  description = "Azure Blob containers required by the deployment. No storage account is created unless declared."
  type = map(object({
    name = optional(string)
  }))
  default = {}
}
