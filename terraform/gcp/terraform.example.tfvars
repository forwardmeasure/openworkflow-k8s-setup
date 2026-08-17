project_id = "my-openworkflow-project"
region     = "us-east1"
name       = "openworkflow-dev"

master_authorized_networks = [
  { cidr_block = "203.0.113.10/32", display_name = "platform-operator" }
]

deletion_protection        = false
cloudsql_high_availability = false

buckets = {
  backups = {
    versioning     = true
    retention_days = 30
  }
}
