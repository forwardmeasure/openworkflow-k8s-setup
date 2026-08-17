variable "project_id" {
  description = "GCP project that owns the OpenWorkflow platform."
  type        = string
}

variable "region" {
  description = "GCP region for the regional GKE cluster and Cloud SQL."
  type        = string
  default     = "us-east1"
}

variable "name" {
  description = "Short environment name used as a resource prefix."
  type        = string
  default     = "openworkflow"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "root_domain" {
  description = "DNS suffix used by Keycloak and OpenWorkflow routes."
  type        = string
}

variable "acme_email" {
  description = "Contact email used by the ACME ClusterIssuer."
  type        = string
}

variable "acme_server" {
  description = "ACME directory. Start with Let's Encrypt staging."
  type        = string
  default     = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

variable "network_cidr" {
  description = "Primary subnet CIDR used by GKE nodes."
  type        = string
  default     = "10.20.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary subnet CIDR used by Kubernetes pods."
  type        = string
  default     = "10.24.0.0/14"
}

variable "services_cidr" {
  description = "Secondary subnet CIDR used by Kubernetes services."
  type        = string
  default     = "10.28.0.0/20"
}

variable "master_ipv4_cidr" {
  description = "Private GKE control-plane CIDR. Must be a /28 outside other ranges."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the public GKE control-plane endpoint. Empty uses GKE defaults; restrict this for shared environments."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "system_machine_type" {
  description = "Machine type for operator and system workloads."
  type        = string
  default     = "e2-standard-4"
}

variable "workload_machine_type" {
  description = "Machine type for OpenWorkflow, Kafka, and Keycloak workloads."
  type        = string
  default     = "e2-standard-8"
}

variable "system_node_count" {
  description = "Initial regional system node count."
  type        = number
  default     = 1
}

variable "workload_node_count" {
  description = "Initial regional workload node count."
  type        = number
  default     = 1
}

variable "cloudsql_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-custom-2-7680"
}

variable "cloudsql_disk_size_gb" {
  description = "Initial Cloud SQL SSD size."
  type        = number
  default     = 50
}

variable "cloudsql_high_availability" {
  description = "Use a regional Cloud SQL instance."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Protect GKE and Cloud SQL resources from accidental deletion."
  type        = bool
  default     = true
}

variable "observability_enabled" {
  description = "Install kube-prometheus-stack during cluster bootstrap."
  type        = bool
  default     = true
}

variable "kafka_storage_size" {
  description = "Persistent volume size for each Kafka controller and broker."
  type        = string
  default     = "100Gi"
}

variable "keycloak_replicas" {
  description = "Number of Keycloak replicas. Use at least two in production."
  type        = number
  default     = 2
}
