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
  fei_input_documents = {
    name = "your-project-fei-input-documents"
  }
  fei_output_documents = {
    name = "your-project-fei-output-documents"
  }
  fei_evidence = {
    name = "your-project-fei-evidence"
  }
}

# The platform control-plane database (tenant_registry, Pekko's cluster-wide coordinator store) plus
# Keycloak's and Superset's own. No product has a database of its own: tenant databases
# (forwardmeasure_<alias>) and every product's runtime role are created by the migration Jobs.
databases = {
  forwardmeasure_control_plane = {
    database         = "forwardmeasure_control_plane"
    runtime_username = "forwardmeasure_control_plane"
  }
  keycloak = {
    database         = "keycloak"
    runtime_username = "keycloak"
  }
  superset = {
    database         = "superset"
    runtime_username = "superset"
  }
}

# Login roles for platform components that own their own database - see variables.tf. Supply the
# passwords (each component's real database password) write-only at plan/apply time:
# export TF_VAR_cloudsql_user_passwords='{"keycloak":"...","superset":"..."}'
cloudsql_users = {
  keycloak = {
    password_version = 1
  }
  superset = {
    password_version = 1
  }
}

# The admin every product's migration Job connects as. Terraform generates its password and stores
# it in Secret Manager as <name>-database-administrator.
database_administrator_username = "forwardmeasure_admin"

# Namespaces must be the ones the charts really deploy into: Workload Identity matches
# PROJECT.svc.id.goog[<namespace>/<ksa>] exactly.
workload_identities = {
  runtime = {
    namespace             = "forwardmeasure-openworkflow"
    service_account       = "openworkflow-runtime"
    bucket_keys           = ["backups"]
    runtime_database_keys = ["forwardmeasure_control_plane"]
    project_roles         = ["roles/cloudsql.client"]
  }
  # forwardmeasure-entity-intelligence's REST services - Cloud SQL Auth Proxy only, password auth as
  # the entityintelligence role, no database of its own. Account id is truncated to 30 characters:
  # <name>-entity-intel.
  entity_intelligence = {
    namespace          = "entity-intelligence"
    service_account    = "entity-intelligence"
    project_roles      = ["roles/cloudsql.client"]
    bucket_keys        = ["fei_output_documents", "fei_evidence"]
    reader_bucket_keys = ["fei_input_documents"]
  }
  # forwardmeasure-decision-engine's gRPC server - its Cloud SQL Auth Proxy sidecar connects to the
  # platform control-plane database (tenant_registry) and each tenant's database as the
  # decision_engine role (password auth; this identity only authorizes the proxy). No database of
  # its own, so no runtime/administrator database keys. Account id is truncated to 30 characters:
  # <name>-decision-eng.
  decision_engine = {
    namespace       = "decision-engine"
    service_account = "decision-engine"
    project_roles   = ["roles/cloudsql.client"]
  }
  migrations = {
    namespace                   = "forwardmeasure-openworkflow"
    service_account             = "openworkflow-database-migration"
    administrator_database_keys = ["forwardmeasure_control_plane", "keycloak", "superset"]
    runtime_database_keys       = ["forwardmeasure_control_plane", "keycloak", "superset"]
    project_roles               = ["roles/cloudsql.client"]
  }
}
