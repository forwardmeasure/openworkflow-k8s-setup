variable "project_id" {
  description = "GCP project that owns the OpenWorkflow infrastructure."
  type        = string
}

variable "region" {
  description = "GCP region for GKE, Cloud SQL, and buckets."
  type        = string
  default     = "us-east1"
}

variable "name" {
  description = "Short environment name used as a resource prefix."
  type        = string
  default     = "openworkflow-dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "network_cidr" {
  type    = string
  default = "10.20.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.24.0.0/14"
}

variable "services_cidr" {
  type    = string
  default = "10.28.0.0/20"
}

variable "master_ipv4_cidr" {
  type    = string
  default = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the public GKE control-plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "At least one operator CIDR must be supplied."
  }
}

variable "cluster_administrator_members" {
  description = "Google IAM members granted Kubernetes Engine administrator access, for example group:platform@example.com."
  type        = set(string)

  validation {
    condition     = length(var.cluster_administrator_members) > 0
    error_message = "At least one durable GKE administrator IAM member must be supplied."
  }
}

variable "system_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "workload_machine_type" {
  type    = string
  default = "e2-standard-8"
}

variable "system_node_count" {
  type    = number
  default = 3
}

variable "workload_node_count" {
  type    = number
  default = 3
}

variable "cloudsql_tier" {
  type    = string
  default = "db-custom-2-7680"
}

variable "cloudsql_disk_size_gb" {
  type    = number
  default = 50
}

variable "cloudsql_high_availability" {
  type    = bool
  default = true
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "databases" {
  description = "PostgreSQL databases and the least-privilege runtime roles that the downstream database-migration service must create."
  type = map(object({
    database         = string
    runtime_username = string
  }))
  default = {
    kafka_streams = {
      database         = "openworkflow_kafka_streams"
      runtime_username = "openworkflow_kafka"
    }
    actor_engine = {
      database         = "openworkflow_actor_engine"
      runtime_username = "openworkflow_actor"
    }
  }
}

variable "database_administrator_username" {
  description = "Cloud SQL administrator used only by database migration and runtime-role provisioning."
  type        = string
  default     = "openworkflow_migration"
}

variable "workload_identities" {
  description = "Cloud IAM identities to create for Kubernetes service accounts owned by the downstream deployment layer."
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
  description = "GCS buckets required by the deployment. No bucket is created unless declared."
  type = map(object({
    name           = optional(string)
    force_destroy  = optional(bool, false)
    versioning     = optional(bool, true)
    retention_days = optional(number, 0)
    labels         = optional(map(string), {})
  }))
  default = {}
}
