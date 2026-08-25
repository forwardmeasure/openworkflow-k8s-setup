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

variable "node_service_account_roles" {
  description = "IAM roles granted to the GKE node service account, project-wide."
  type        = set(string)
  default = [
    "roles/cloudsql.client",
    "roles/storage.admin",
    "roles/artifactregistry.reader",
    "roles/artifactregistry.writer",
    "roles/container.nodeServiceAccount",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/compute.viewer",
    "roles/compute.networkUser",
    "roles/dns.admin",
    "roles/iam.serviceAccountTokenCreator",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ]
}

variable "cluster_operating_role_permissions" {
  description = "Granular permissions bundled into a custom IAM role for CI/automation identities that need narrower access than roles/container.admin (granted via cluster_administrator_members). No role is created if this is empty."
  type        = list(string)
  default = [
    "iam.roles.list",
    "iam.roles.create",
    "iam.roles.delete",
    "compute.networks.create",
    "compute.projects.get",
    "container.clusters.get",
    "container.clusters.list",
    "container.pods.get",
    "container.pods.getLogs",
    "container.pods.list",
    "container.thirdPartyObjects.create",
    "container.thirdPartyObjects.delete",
    "iam.serviceAccounts.create",
    "resourcemanager.projects.get",
    "servicemanagement.services.check",
    "servicemanagement.services.get",
    "servicemanagement.services.report",
    "serviceusage.quotas.get",
    "serviceusage.services.get",
    "serviceusage.services.list",
  ]
}

variable "cluster_operator_members" {
  description = "Google IAM members bound to the cluster_operating_role_permissions custom role, for example serviceAccount:ci@example.iam.gserviceaccount.com. Separate from cluster_administrator_members, which gets full roles/container.admin instead."
  type        = set(string)
  default     = []
}

variable "node_pools" {
  description = "GKE node pools, keyed by pool name. Each entry is an independently scaled managed node pool; add, remove, or reshape pools here without touching main.tf. GPU fields are optional and only take effect when gpu_type is set."
  type = map(object({
    machine_type       = string
    image_type         = optional(string, "COS_CONTAINERD")
    node_locations     = optional(list(string), [])
    disk_type          = optional(string, "pd-balanced")
    disk_size_gb       = optional(number, 100)
    min_node_count     = optional(number, 1)
    max_node_count     = optional(number, 3)
    initial_node_count = optional(number)
    preemptible        = optional(bool, false)
    spot               = optional(bool, false)
    local_ssd_count    = optional(number, 0)
    # Separate from local_ssd_count above (the legacy node_config attribute):
    # some machine types (e.g. a3-highgpu-1g) have local NVMe SSDs baked
    # into the hardware shape, which GCP reports back via the newer
    # ephemeral_storage_local_ssd_config block regardless of what's
    # declared. Leave this null for pools with no mandatory local SSDs -
    # setting it only where GCP's own live state requires it avoids a
    # perpetual destroy/recreate loop (declared vs enforced never
    # converging).
    ephemeral_storage_local_ssd_count = optional(number)
    labels                            = optional(map(string), {})
    tags                              = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    gpu_type           = optional(string)
    gpu_count          = optional(number, 1)
    gpu_driver_version = optional(string, "DEFAULT")
  }))

  default = {
    system = {
      machine_type   = "e2-standard-4"
      min_node_count = 3
      max_node_count = 3
      disk_size_gb   = 100
      labels         = { "openworkflow.io/pool" = "system" }
    }
    workloads = {
      machine_type   = "e2-standard-8"
      min_node_count = 3
      max_node_count = 9
      disk_size_gb   = 200
      labels         = { "openworkflow.io/pool" = "workloads" }
    }
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : pool.min_node_count <= pool.max_node_count])
    error_message = "Every node pool's min_node_count must be less than or equal to its max_node_count."
  }
}

variable "cloudsql_version" {
  type    = string
  default = "POSTGRES_17"
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
    namespace       = string
    service_account = string
    # Extra (namespace, service_account) pairs impersonating this same GSA -
    # e.g. model-serving's GSA is annotated onto both the model-cache and
    # docling KSAs in forwardmeasure-platform, since docling shares the same
    # model service account rather than getting its own.
    additional_bindings = optional(list(object({
      namespace       = string
      service_account = string
    })), [])
    bucket_keys                 = optional(set(string), [])
    administrator_database_keys = optional(set(string), [])
    runtime_database_keys       = optional(set(string), [])
    # Project-level IAM roles this identity needs beyond bucket/database
    # access - e.g. roles/dns.admin for cert-manager's DNS-01 solver,
    # roles/secretmanager.secretAccessor for external-secrets. Most
    # identities need none of this; it's for platform-level workloads that
    # aren't scoped to a single declared bucket or database.
    project_roles = optional(set(string), [])
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

variable "dns_zone_name" {
  description = "Cloud DNS managed zone (GCP resource name, not the domain itself) that resolves this cluster's public hostnames. Already exists - never created by this module, only read via data source."
  type        = string
}

variable "gateway_static_ip_name" {
  description = "Reserved external IP address (GCP resource name) that the platform Gateway's LoadBalancer service binds to. Already exists - never created by this module, only read via data source."
  type        = string
}
