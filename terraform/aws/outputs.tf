output "cluster_name" { value = module.eks.cluster_name }
output "cluster_location" { value = var.region }
output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}
output "cloud_account_id" { value = data.aws_caller_identity.current.account_id }
output "network_id" { value = module.vpc.vpc_id }
output "cluster_subnet_ids" { value = module.vpc.private_subnets }
output "database_subnet_ids" { value = module.vpc.database_subnets }
output "workload_identity_issuer" { value = module.eks.cluster_oidc_issuer_url }
output "database_hosts" { value = { for key, value in aws_db_instance.platform : key => value.address } }
output "database_port" { value = 5432 }
output "database_names" { value = { for key, value in var.databases : key => value.database_name } }
output "database_ssl_mode" { value = "verify-full" }
output "database_ca_certificate_identifiers" {
  value = { for key, value in aws_db_instance.platform : key => value.ca_cert_identifier }
}
output "database_role_provisioning_required" { value = true }
output "database_administrator_usernames" {
  value = { for key, value in var.databases : key => value.administrator_username }
}
output "database_administrator_secret_ids" {
  value = { for key, value in aws_db_instance.platform : key => value.master_user_secret[0].secret_arn }
}
output "database_runtime_usernames" {
  value = { for key, value in var.databases : key => value.runtime_username }
}
output "database_runtime_secret_ids" {
  value = { for key, value in aws_secretsmanager_secret.database_runtime : key => value.arn }
}
output "bucket_names" { value = { for key, value in aws_s3_bucket.platform : key => value.bucket } }
output "bucket_ids" { value = { for key, value in aws_s3_bucket.platform : key => value.id } }
output "bucket_uris" { value = { for key, value in aws_s3_bucket.platform : key => "s3://${value.bucket}" } }
output "workload_identity_bindings" {
  value = {
    for key, value in var.workload_identities : key => {
      namespace                   = value.namespace
      kubernetes_service_account  = value.service_account
      cloud_principal             = aws_iam_role.workload[key].arn
      service_account_annotation  = "eks.amazonaws.com/role-arn=${aws_iam_role.workload[key].arn}"
      bucket_keys                 = sort(tolist(value.bucket_keys))
      administrator_database_keys = sort(tolist(value.administrator_database_keys))
      runtime_database_keys       = sort(tolist(value.runtime_database_keys))
    }
  }
}
output "kubeconfig_command" { value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}" }

output "deployment_handoff" {
  sensitive = true
  value = {
    cloud_provider = "aws"
    cloud_scope    = data.aws_caller_identity.current.account_id
    cluster = {
      name                     = module.eks.cluster_name
      location                 = var.region
      endpoint                 = module.eks.cluster_endpoint
      network_id               = module.vpc.vpc_id
      subnet_ids               = module.vpc.private_subnets
      workload_identity_issuer = module.eks.cluster_oidc_issuer_url
    }
    databases = {
      for key, database in var.databases : key => {
        host                       = aws_db_instance.platform[key].address
        port                       = 5432
        name                       = database.database_name
        ssl_mode                   = "verify-full"
        administrator_username     = database.administrator_username
        administrator_secret_id    = aws_db_instance.platform[key].master_user_secret[0].secret_arn
        runtime_username           = database.runtime_username
        runtime_secret_id          = aws_secretsmanager_secret.database_runtime[key].arn
        role_provisioning_required = true
      }
    }
    object_storage = {
      for key, bucket in aws_s3_bucket.platform : key => {
        name = bucket.bucket
        id   = bucket.id
        uri  = "s3://${bucket.bucket}"
      }
    }
    workload_identities = {
      for key, identity in var.workload_identities : key => {
        namespace                  = identity.namespace
        kubernetes_service_account = identity.service_account
        cloud_principal            = aws_iam_role.workload[key].arn
        service_account_annotation = "eks.amazonaws.com/role-arn=${aws_iam_role.workload[key].arn}"
      }
    }
  }
}
