output "cluster_name" { value = google_container_cluster.platform.name }
output "cluster_location" { value = google_container_cluster.platform.location }
output "project_id" { value = var.project_id }
output "database_hosts" {
  value = {
    for key, _ in var.databases : key => google_sql_database_instance.platform.private_ip_address
  }
}
output "database_port" { value = 5432 }
output "database_names" { value = { for key, value in var.databases : key => value.database } }
output "database_usernames" { value = { for key, value in var.databases : key => value.username } }
output "database_passwords" {
  value     = { for key, value in random_password.database : key => value.result }
  sensitive = true
}
output "bucket_names" { value = { for key, value in google_storage_bucket.platform : key => value.name } }
output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.platform.name} --project ${var.project_id} --region ${var.region}"
}
