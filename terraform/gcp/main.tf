locals {
  required_services = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])
  pods_range_name     = "${var.name}-pods"
  services_range_name = "${var.name}-services"
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

resource "google_project_service" "required" {
  for_each           = local.required_services
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "platform" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.required]
}

resource "google_compute_subnetwork" "platform" {
  project                  = var.project_id
  name                     = "${var.name}-subnet"
  region                   = var.region
  network                  = google_compute_network.platform.id
  ip_cidr_range            = var.network_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pods_range_name
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = local.services_range_name
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_router" "platform" {
  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.platform.id
}

resource "google_compute_router_nat" "platform" {
  project                            = var.project_id
  name                               = "${var.name}-nat"
  region                             = var.region
  router                             = google_compute_router.platform.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.platform.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = substr("${var.name}-gke-nodes", 0, 30)
  display_name = "${var.name} GKE nodes"
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_administrators" {
  for_each = var.cluster_administrator_members

  project = var.project_id
  role    = "roles/container.admin"
  member  = each.value
}

resource "google_container_cluster" "platform" {
  project                  = var.project_id
  name                     = var.name
  location                 = var.region
  network                  = google_compute_network.platform.id
  subnetwork               = google_compute_subnetwork.platform.id
  deletion_protection      = var.deletion_protection
  remove_default_node_pool = true
  initial_node_count       = 1
  enable_shielded_nodes    = true
  networking_mode          = "VPC_NATIVE"

  release_channel {
    channel = "REGULAR"
  }
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }
  addons_config {
    dns_cache_config {
      enabled = true
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  depends_on = [google_compute_router_nat.platform, google_project_iam_member.gke_nodes]
}

resource "google_container_node_pool" "system" {
  project    = var.project_id
  name       = "system"
  location   = var.region
  cluster    = google_container_cluster.platform.name
  node_count = var.system_node_count

  autoscaling {
    total_min_node_count = var.system_node_count
    total_max_node_count = max(var.system_node_count, 3)
  }
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  node_config {
    machine_type    = var.system_machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = { "openworkflow.io/pool" = "system" }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }
  }
}

resource "google_container_node_pool" "workloads" {
  project    = var.project_id
  name       = "workloads"
  location   = var.region
  cluster    = google_container_cluster.platform.name
  node_count = var.workload_node_count

  autoscaling {
    total_min_node_count = var.workload_node_count
    total_max_node_count = max(var.workload_node_count, 9)
  }
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  node_config {
    machine_type    = var.workload_machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = 200
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = { "openworkflow.io/pool" = "workloads" }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }
  }
}

resource "google_compute_global_address" "private_services" {
  project       = var.project_id
  name          = "${var.name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.platform.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.platform.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_sql_database_instance" "platform" {
  project             = var.project_id
  name                = "${var.name}-postgres"
  region              = var.region
  database_version    = "POSTGRES_17"
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.cloudsql_tier
    availability_type = var.cloudsql_high_availability ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.cloudsql_disk_size_gb
    disk_autoresize   = true
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.platform.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "04:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }
  }
  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "platform" {
  for_each = var.databases
  project  = var.project_id
  instance = google_sql_database_instance.platform.name
  name     = each.value.database
}

resource "random_password" "database_administrator" {
  length  = 40
  special = false
}

resource "google_sql_user" "database_administrator" {
  project  = var.project_id
  instance = google_sql_database_instance.platform.name
  name     = var.database_administrator_username
  password = random_password.database_administrator.result
}

resource "random_password" "database_runtime" {
  for_each = var.databases
  length   = 40
  special  = false
}

resource "google_secret_manager_secret" "database_administrator" {
  project   = var.project_id
  secret_id = "${var.name}-database-administrator"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "database_administrator" {
  secret      = google_secret_manager_secret.database_administrator.id
  secret_data = random_password.database_administrator.result
}

resource "google_secret_manager_secret" "database_runtime" {
  for_each = var.databases

  project   = var.project_id
  secret_id = "${var.name}-${replace(each.key, "_", "-")}-runtime"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "database_runtime" {
  for_each = var.databases

  secret      = google_secret_manager_secret.database_runtime[each.key].id
  secret_data = random_password.database_runtime[each.key].result
}

resource "google_storage_bucket" "platform" {
  for_each                    = var.buckets
  project                     = var.project_id
  name                        = coalesce(each.value.name, trim(substr("${var.project_id}-${var.name}-${replace(each.key, "_", "-")}", 0, 63), "-"))
  location                    = var.region
  force_destroy               = each.value.force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = merge({ purpose = each.key }, each.value.labels)

  versioning {
    enabled = each.value.versioning
  }
  dynamic "retention_policy" {
    for_each = each.value.retention_days > 0 ? [each.value.retention_days] : []
    content {
      retention_period = retention_policy.value * 86400
      is_locked        = false
    }
  }
}

resource "google_service_account" "workload" {
  for_each = var.workload_identities

  project      = var.project_id
  account_id   = substr("${var.name}-${replace(each.key, "_", "-")}", 0, 30)
  display_name = "${var.name} ${each.key} workload"
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.workload_identities

  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.service_account}]"
}

resource "google_storage_bucket_iam_member" "workload" {
  for_each = local.workload_bucket_bindings

  bucket = google_storage_bucket.platform[each.value.bucket_key].name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.workload[each.value.identity_key].email}"
}

resource "google_secret_manager_secret_iam_member" "workload_database_administrator" {
  for_each = {
    for key, value in var.workload_identities : key => value
    if length(value.administrator_database_keys) > 0
  }

  project   = var.project_id
  secret_id = google_secret_manager_secret.database_administrator.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload[each.key].email}"
}

resource "google_secret_manager_secret_iam_member" "workload_database_runtime" {
  for_each = local.workload_runtime_secret_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.database_runtime[each.value.database_key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload[each.value.identity_key].email}"
}

check "database_names_are_unique" {
  assert {
    condition     = length(distinct([for database in values(var.databases) : database.database])) == length(var.databases)
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
