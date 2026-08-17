output "cluster_name" { value = google_container_cluster.platform.name }
output "cluster_location" { value = google_container_cluster.platform.location }
output "cluster_endpoint" {
  value     = google_container_cluster.platform.endpoint
  sensitive = true
}
output "project_id" { value = var.project_id }
output "network_id" { value = google_compute_network.platform.id }
output "cluster_subnet_ids" { value = [google_compute_subnetwork.platform.id] }
output "workload_identity_issuer" { value = "${var.project_id}.svc.id.goog" }
output "database_private_service_range" {
  value = {
    address       = google_compute_global_address.private_services.address
    prefix_length = google_compute_global_address.private_services.prefix_length
  }
}
output "database_hosts" {
  value = {
    for key, _ in var.databases : key => google_sql_database_instance.platform.private_ip_address
  }
}
output "database_port" { value = 5432 }
output "database_names" { value = { for key, value in var.databases : key => value.database } }
output "database_ssl_mode" { value = "verify-ca" }
output "database_server_ca_certificates" {
  value     = { for key, _ in var.databases : key => google_sql_database_instance.platform.server_ca_cert[0].cert }
  sensitive = true
}
output "database_role_provisioning_required" { value = true }
output "database_administrator_usernames" {
  value = { for key, _ in var.databases : key => var.database_administrator_username }
}
output "database_administrator_secret_ids" {
  value = { for key, _ in var.databases : key => google_secret_manager_secret.database_administrator.id }
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
    for key, value in var.workload_identities : key => {
      namespace                   = value.namespace
      kubernetes_service_account  = value.service_account
      cloud_principal             = google_service_account.workload[key].email
      service_account_annotation  = "iam.gke.io/gcp-service-account=${google_service_account.workload[key].email}"
      bucket_keys                 = sort(tolist(value.bucket_keys))
      administrator_database_keys = sort(tolist(value.administrator_database_keys))
      runtime_database_keys       = sort(tolist(value.runtime_database_keys))
    }
  }
}
output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.platform.name} --project ${var.project_id} --region ${var.region}"
}

output "deployment_handoff" {
  sensitive = true
  value = {
    cloud_provider = "gcp"
    cloud_scope    = var.project_id
    cluster = {
      name                     = google_container_cluster.platform.name
      location                 = google_container_cluster.platform.location
      endpoint                 = google_container_cluster.platform.endpoint
      network_id               = google_compute_network.platform.id
      subnet_ids               = [google_compute_subnetwork.platform.id]
      workload_identity_issuer = "${var.project_id}.svc.id.goog"
    }
    databases = {
      for key, database in var.databases : key => {
        host                       = google_sql_database_instance.platform.private_ip_address
        port                       = 5432
        name                       = database.database
        ssl_mode                   = "verify-ca"
        administrator_username     = var.database_administrator_username
        administrator_secret_id    = google_secret_manager_secret.database_administrator.id
        runtime_username           = database.runtime_username
        runtime_secret_id          = google_secret_manager_secret.database_runtime[key].id
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
      for key, identity in var.workload_identities : key => {
        namespace                  = identity.namespace
        kubernetes_service_account = identity.service_account
        cloud_principal            = google_service_account.workload[key].email
        service_account_annotation = "iam.gke.io/gcp-service-account=${google_service_account.workload[key].email}"
      }
    }
  }
}
