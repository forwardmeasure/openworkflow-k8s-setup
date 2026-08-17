project_id = "my-openworkflow-project"
region     = "us-east1"
name       = "openworkflow-prod"

master_authorized_networks = [
  { cidr_block = "203.0.113.10/32", display_name = "platform-operator" }
]

cluster_administrator_members = ["group:platform-operators@example.com"]

buckets = {
  backups = {
    versioning     = true
    retention_days = 30
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
