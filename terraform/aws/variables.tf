variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "openworkflow-dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Operator CIDRs allowed to reach the public EKS API endpoint."
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "At least one operator CIDR must be supplied."
  }
}

variable "cluster_administrator_principal_arns" {
  description = "Durable IAM role ARNs granted EKS cluster-administrator access."
  type        = set(string)

  validation {
    condition     = length(var.cluster_administrator_principal_arns) > 0
    error_message = "At least one durable EKS administrator IAM role ARN must be supplied."
  }
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "system_instance_types" {
  type    = list(string)
  default = ["m7i.xlarge"]
}

variable "workload_instance_types" {
  type    = list(string)
  default = ["m7i.2xlarge"]
}

variable "single_nat_gateway" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  description = "Skip the final RDS snapshot on destruction. Keep false outside disposable environments."
  type        = bool
  default     = false
}

variable "databases" {
  description = "RDS instances, migration administrators, and least-privilege runtime roles created later by the database-migration service."
  type = map(object({
    database_name          = string
    administrator_username = string
    runtime_username       = string
    instance_class         = optional(string, "db.m7g.large")
    allocated_storage      = optional(number, 100)
    multi_az               = optional(bool, true)
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
}

variable "workload_identities" {
  description = "IRSA roles to create for Kubernetes service accounts owned by the downstream deployment layer."
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
  description = "S3 buckets required by the deployment. No bucket is created unless declared."
  type = map(object({
    name            = optional(string)
    force_destroy   = optional(bool, false)
    versioning      = optional(bool, true)
    expiration_days = optional(number, 0)
    noncurrent_days = optional(number, 30)
    tags            = optional(map(string), {})
  }))
  default = {}
}
