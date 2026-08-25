mock_provider "google" {
  mock_resource "google_compute_network" {
    defaults = {
      id = "projects/openworkflow-test/global/networks/openworkflow-test-vpc"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/openworkflow-test/serviceAccounts/openworkflow-test@openworkflow-test.iam.gserviceaccount.com"
      email = "openworkflow-test@openworkflow-test.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_sql_database_instance" {
    defaults = {
      private_ip_address = "10.20.0.10"
      server_ca_cert = [
        {
          cert             = "test-ca-certificate"
          common_name      = "openworkflow-test"
          create_time      = "2026-01-01T00:00:00Z"
          expiration_time  = "2036-01-01T00:00:00Z"
          sha1_fingerprint = "0000000000000000000000000000000000000000"
        }
      ]
    }
  }
}

mock_provider "random" {}

run "production_contract" {
  command = plan

  variables {
    project_id = "openworkflow-test"
    name       = "openworkflow-test"
    master_authorized_networks = [
      { cidr_block = "203.0.113.10/32", display_name = "test-operator" }
    ]
    cluster_administrator_members = ["group:platform-operators@example.com"]
    buckets = {
      backups = {
        retention_days = 30
      }
    }
    # Explicit, not relying on the variable's default or a real environment's
    # terraform.tfvars - this test must stay self-contained regardless of
    # what real database names change to.
    databases = {
      kafka_streams = {
        database         = "openworkflow_kafka_streams"
        runtime_username = "openworkflow_kafka"
      }
      actor_engine = {
        database         = "openworkflow_actor_engine"
        runtime_username = "openworkflow_actor"
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
  }

  assert {
    condition     = google_sql_database_instance.platform.settings[0].availability_type == "REGIONAL"
    error_message = "The production contract must enable regional Cloud SQL availability."
  }

  assert {
    condition     = google_container_cluster.platform.deletion_protection
    error_message = "The production contract must protect the GKE cluster from deletion."
  }

  assert {
    condition     = output.database_role_provisioning_required
    error_message = "The handoff must require creation of least-privilege runtime roles."
  }
}
