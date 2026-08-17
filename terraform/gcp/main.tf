locals {
  required_services = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
  ])

  pods_range_name     = "${var.name}-pods"
  services_range_name = "${var.name}-services"

  databases = {
    keycloak = {
      database  = "keycloak"
      username  = "keycloak"
      secret_id = "${var.name}-keycloak-database"
    }
    kafka_streams = {
      database  = "openworkflow_kafka_streams"
      username  = "openworkflow_kafka"
      secret_id = "${var.name}-kafka-streams-database"
    }
    actor_engine = {
      database  = "openworkflow_actor_engine"
      username  = "openworkflow_actor"
      secret_id = "${var.name}-actor-engine-database"
    }
  }
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "platform" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "platform" {
  project       = var.project_id
  name          = "${var.name}-subnet"
  region        = var.region
  network       = google_compute_network.platform.id
  ip_cidr_range = var.network_cidr

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

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
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

resource "google_compute_address" "gateway" {
  project      = var.project_id
  name         = "${var.name}-gateway"
  region       = var.region
  address_type = "EXTERNAL"
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

resource "google_container_cluster" "platform" {
  project  = var.project_id
  name     = var.name
  location = var.region

  network    = google_compute_network.platform.id
  subnetwork = google_compute_subnetwork.platform.id

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

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) == 0 ? [] : [1]
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
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

  maintenance_policy {
    recurring_window {
      start_time = "2026-01-04T05:00:00Z"
      end_time   = "2026-01-04T09:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  depends_on = [
    google_compute_router_nat.platform,
    google_project_iam_member.gke_nodes,
    google_project_service.required,
  ]
}

resource "google_container_node_pool" "system" {
  project  = var.project_id
  name     = "system"
  location = var.region
  cluster  = google_container_cluster.platform.name

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

    labels = {
      "openworkflow.io/pool" = "system"
    }

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
  project  = var.project_id
  name     = "workloads"
  location = var.region
  cluster  = google_container_cluster.platform.name

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

    labels = {
      "openworkflow.io/pool" = "workloads"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }
  }
}

resource "google_sql_database_instance" "platform" {
  project             = var.project_id
  name                = "${var.name}-postgres"
  region              = var.region
  database_version    = "POSTGRES_18"
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.cloudsql_tier
    availability_type = var.cloudsql_high_availability ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.cloudsql_disk_size_gb
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.platform.id
      enable_private_path_for_google_cloud_services = true
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

    maintenance_window {
      day          = 7
      hour         = 5
      update_track = "stable"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "platform" {
  for_each = local.databases

  project  = var.project_id
  instance = google_sql_database_instance.platform.name
  name     = each.value.database
}

resource "random_password" "database" {
  for_each = local.databases

  length  = 32
  special = false
}

resource "google_sql_user" "platform" {
  for_each = local.databases

  project  = var.project_id
  instance = google_sql_database_instance.platform.name
  name     = each.value.username
  password = random_password.database[each.key].result
}

resource "random_password" "keycloak_admin" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "database" {
  for_each = local.databases

  project   = var.project_id
  secret_id = each.value.secret_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database" {
  for_each = local.databases

  secret = google_secret_manager_secret.database[each.key].id
  secret_data = jsonencode({
    username = each.value.username
    password = random_password.database[each.key].result
  })
}

resource "google_secret_manager_secret" "kafka_streams_username" {
  project   = var.project_id
  secret_id = "${var.name}-kafka-streams-database-username"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "kafka_streams_username" {
  secret      = google_secret_manager_secret.kafka_streams_username.id
  secret_data = local.databases.kafka_streams.username
}

resource "google_secret_manager_secret" "kafka_streams_password" {
  project   = var.project_id
  secret_id = "${var.name}-kafka-streams-database-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "kafka_streams_password" {
  secret      = google_secret_manager_secret.kafka_streams_password.id
  secret_data = random_password.database["kafka_streams"].result
}

resource "google_secret_manager_secret" "keycloak_admin" {
  project   = var.project_id
  secret_id = "${var.name}-keycloak-admin"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "keycloak_admin" {
  secret = google_secret_manager_secret.keycloak_admin.id
  secret_data = jsonencode({
    username = "platform-admin"
    password = random_password.keycloak_admin.result
  })
}

resource "google_service_account" "external_secrets" {
  project      = var.project_id
  account_id   = substr("${var.name}-external-secrets", 0, 30)
  display_name = "${var.name} External Secrets"
}

resource "google_secret_manager_secret_iam_member" "external_secrets_database_accessor" {
  for_each = google_secret_manager_secret.database

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}

resource "google_secret_manager_secret_iam_member" "external_secrets_keycloak_admin_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.keycloak_admin.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}

resource "google_secret_manager_secret_iam_member" "external_secrets_kafka_username_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.kafka_streams_username.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}

resource "google_secret_manager_secret_iam_member" "external_secrets_kafka_password_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.kafka_streams_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}

resource "google_service_account_iam_member" "external_secrets_workload_identity" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}
