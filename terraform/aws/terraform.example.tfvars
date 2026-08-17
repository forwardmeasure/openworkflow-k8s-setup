region = "us-east-1"
name   = "openworkflow-prod"

cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
cluster_administrator_principal_arns = ["arn:aws:iam::123456789012:role/platform-operators"]

buckets = {
  backups = {
    versioning      = true
    expiration_days = 365
    noncurrent_days = 30
  }
}

workload_identities = {
  runtime = {
    namespace             = "openworkflow"
    service_account       = "openworkflow-runtime"
    bucket_keys           = ["backups"]
    runtime_database_keys = ["kafka_streams"]
  }
  migrations = {
    namespace                   = "openworkflow"
    service_account             = "openworkflow-database-migration"
    administrator_database_keys = ["kafka_streams", "actor_engine"]
    runtime_database_keys       = ["kafka_streams", "actor_engine"]
  }
}
