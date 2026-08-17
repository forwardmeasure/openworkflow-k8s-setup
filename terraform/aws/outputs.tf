output "cluster_name" { value = module.eks.cluster_name }
output "cluster_location" { value = var.region }
output "database_hosts" { value = { for key, value in aws_db_instance.platform : key => value.address } }
output "database_port" { value = 5432 }
output "database_names" { value = { for key, value in var.databases : key => value.database_name } }
output "database_usernames" { value = { for key, value in var.databases : key => value.username } }
output "database_passwords" {
  value     = { for key, value in random_password.database : key => value.result }
  sensitive = true
}
output "bucket_names" { value = { for key, value in aws_s3_bucket.platform : key => value.bucket } }
output "kubeconfig_command" { value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}" }
