# Every output below tolerates partial state (some resources destroyed,
# others not) without hard-failing - `try(..., <fallback>)` around any
# reference to a resource that can be destroyed independently of the
# others, and for-each loops keyed off the actual resource maps
# (google_service_account.workload, google_secret_manager_secret.
# database_runtime, google_storage_bucket.platform) rather than the
# declaring variables (var.workload_identities, var.databases). A
# for-each keyed off a variable assumes every declared entry still has a
# matching resource in state; that's false mid-destroy (or after a
# partial apply), and one broken output fails the *entire* plan/apply/
# refresh - including unrelated outputs like project_id - since OpenTofu
# evaluates all outputs together. Confirmed the hard way: workload_identity_
# bindings/deployment_handoff's old var-keyed loops broke `tofu apply
# -refresh-only` entirely once the workload service accounts were destroyed
# but other resources weren't yet, which cascaded into the Makefile's own
# `tofu output -raw project_id` coming back empty.
output "cluster_name" { value = try(google_container_cluster.platform.name, null) }
output "cluster_location" { value = try(google_container_cluster.platform.location, null) }
output "cluster_endpoint" {
  value     = try(google_container_cluster.platform.endpoint, null)
  sensitive = true
}
output "project_id" { value = var.project_id }
output "network_id" { value = try(google_compute_network.platform.id, null) }
output "cluster_subnet_ids" { value = try([google_compute_subnetwork.platform.id], []) }
output "workload_identity_issuer" { value = "${var.project_id}.svc.id.goog" }
output "database_private_service_range" {
  value = try({
    address       = google_compute_global_address.private_services.address
    prefix_length = google_compute_global_address.private_services.prefix_length
  }, null)
}
output "database_hosts" {
  value = { for key, _ in var.databases : key => try(google_sql_database_instance.platform.private_ip_address, null) }
}
output "database_port" { value = 5432 }
output "database_connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance) for the Cloud SQL Auth Proxy's --instances flag. One instance hosts every database in var.databases."
  value       = try(google_sql_database_instance.platform.connection_name, null)
}
output "database_names" { value = { for key, value in var.databases : key => value.database } }
output "database_ssl_mode" { value = "verify-ca" }
output "database_server_ca_certificates" {
  value     = { for key, _ in var.databases : key => try(google_sql_database_instance.platform.server_ca_cert[0].cert, null) }
  sensitive = true
}
output "database_role_provisioning_required" { value = true }
output "database_administrator_usernames" {
  value = { for key, _ in var.databases : key => var.database_administrator_username }
}
output "database_administrator_secret_ids" {
  value = { for key, _ in var.databases : key => try(google_secret_manager_secret.database_administrator.id, null) }
}
output "database_runtime_usernames" {
  value = { for key, value in var.databases : key => value.runtime_username }
}
output "database_runtime_secret_ids" {
  value = { for key, value in google_secret_manager_secret.database_runtime : key => value.id }
}
output "bucket_names" { value = { for key, value in google_storage_bucket.platform : key => value.name } }
output "bucket_ids" { value = { for key, value in google_storage_bucket.platform : key => value.id } }
output "bucket_uris" { value = { for key, value in google_storage_bucket.platform : key => "gs://${value.name}" } }
output "workload_identity_bindings" {
  value = {
    for key, sa in google_service_account.workload : key => {
      namespace                   = var.workload_identities[key].namespace
      kubernetes_service_account  = var.workload_identities[key].service_account
      cloud_principal             = sa.email
      service_account_annotation  = "iam.gke.io/gcp-service-account=${sa.email}"
      bucket_keys                 = sort(tolist(var.workload_identities[key].bucket_keys))
      administrator_database_keys = sort(tolist(var.workload_identities[key].administrator_database_keys))
      runtime_database_keys       = sort(tolist(var.workload_identities[key].runtime_database_keys))
    }
  }
}
output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${try(google_container_cluster.platform.name, var.name)} --project ${var.project_id} --region ${var.region}"
}

output "deployment_handoff" {
  sensitive = true
  value = {
    cloud_provider = "gcp"
    cloud_scope    = var.project_id
    cluster = {
      name                     = try(google_container_cluster.platform.name, null)
      location                 = try(google_container_cluster.platform.location, null)
      endpoint                 = try(google_container_cluster.platform.endpoint, null)
      network_id               = try(google_compute_network.platform.id, null)
      subnet_ids               = try([google_compute_subnetwork.platform.id], [])
      workload_identity_issuer = "${var.project_id}.svc.id.goog"
    }
    databases = {
      for key, database in var.databases : key => {
        host                       = try(google_sql_database_instance.platform.private_ip_address, null)
        port                       = 5432
        name                       = database.database
        ssl_mode                   = "verify-ca"
        administrator_username     = var.database_administrator_username
        administrator_secret_id    = try(google_secret_manager_secret.database_administrator.id, null)
        runtime_username           = database.runtime_username
        runtime_secret_id          = try(google_secret_manager_secret.database_runtime[key].id, null)
        role_provisioning_required = true
      }
    }
    object_storage = {
      for key, bucket in google_storage_bucket.platform : key => {
        name = bucket.name
        id   = bucket.id
        uri  = "gs://${bucket.name}"
      }
    }
    workload_identities = {
      for key, sa in google_service_account.workload : key => {
        namespace                  = var.workload_identities[key].namespace
        kubernetes_service_account = var.workload_identities[key].service_account
        cloud_principal            = sa.email
        service_account_annotation = "iam.gke.io/gcp-service-account=${sa.email}"
      }
    }
  }
}
