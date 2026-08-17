output "cluster_name" {
  value = google_container_cluster.platform.name
}

output "cluster_location" {
  value = google_container_cluster.platform.location
}

output "project_id" {
  value = var.project_id
}

output "gateway_ip" {
  description = "Create DNS A records for platform hostnames at this address."
  value       = google_compute_address.gateway.address
}

output "cloudsql_private_ip" {
  value = google_sql_database_instance.platform.private_ip_address
}

output "cloudsql_instance_connection_name" {
  value = google_sql_database_instance.platform.connection_name
}

output "external_secrets_service_account_email" {
  value = google_service_account.external_secrets.email
}

output "root_domain" {
  value = var.root_domain
}

output "acme_email" {
  value = var.acme_email
}

output "acme_server" {
  value = var.acme_server
}

output "observability_enabled" {
  value = var.observability_enabled
}

output "kafka_storage_size" {
  value = var.kafka_storage_size
}

output "keycloak_replicas" {
  value = var.keycloak_replicas
}

output "secret_ids" {
  description = "Secret Manager IDs used by ExternalSecret resources."
  value = {
    keycloak_database      = google_secret_manager_secret.database["keycloak"].secret_id
    keycloak_admin         = google_secret_manager_secret.keycloak_admin.secret_id
    kafka_streams_database = google_secret_manager_secret.database["kafka_streams"].secret_id
    kafka_streams_username = google_secret_manager_secret.kafka_streams_username.secret_id
    kafka_streams_password = google_secret_manager_secret.kafka_streams_password.secret_id
    actor_engine_database  = google_secret_manager_secret.database["actor_engine"].secret_id
  }
}

output "database_names" {
  value = { for key, value in local.databases : key => value.database }
}

output "database_usernames" {
  value = { for key, value in local.databases : key => value.username }
}
