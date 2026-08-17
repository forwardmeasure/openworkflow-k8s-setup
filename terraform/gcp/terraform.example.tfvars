project_id  = "my-openworkflow-project"
region      = "us-east1"
name        = "openworkflow-dev"
root_domain = "openworkflow.example.com"
acme_email  = "platform@example.com"

# Keep staging until DNS resolves and the complete flow has been verified.
acme_server = "https://acme-staging-v02.api.letsencrypt.org/directory"

# Restrict the public control-plane endpoint to operator networks.
master_authorized_networks = [
  {
    cidr_block   = "203.0.113.10/32"
    display_name = "platform-operator"
  }
]

# Development settings. Production should normally retain deletion protection,
# Cloud SQL HA, at least two nodes per pool, and three Kafka brokers.
deletion_protection        = false
cloudsql_high_availability = false
system_node_count          = 1
workload_node_count        = 1
observability_enabled      = true
