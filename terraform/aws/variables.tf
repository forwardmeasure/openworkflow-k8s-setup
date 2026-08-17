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
  default = true
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "databases" {
  description = "RDS instances and initial databases. RDS exposes only one control-plane-created database/user per instance."
  type = map(object({
    database_name     = string
    username          = string
    instance_class    = optional(string, "db.m7g.large")
    allocated_storage = optional(number, 100)
    multi_az          = optional(bool, false)
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
