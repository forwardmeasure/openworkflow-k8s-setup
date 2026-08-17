location = "East US"
name     = "openworkflow-prod"

api_server_authorized_ip_ranges = ["203.0.113.10/32"]
aks_admin_group_object_ids      = ["00000000-0000-0000-0000-000000000000"]
geo_redundant_backup_enabled    = false

buckets = {
  backups = {}
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
