mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/opentofu"
      user_id    = "AROA00000000000000000"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:role/opentofu"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition          = "aws"
      dns_suffix         = "amazonaws.com"
      reverse_dns_prefix = "com.amazonaws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json          = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      minified_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/openworkflow-test"
      endpoint = "https://example.eks.amazonaws.com"
      certificate_authority = [
        {
          data = "dGVzdA=="
        }
      ]
      identity = [
        {
          oidc = [
            {
              issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
            }
          ]
        }
      ]
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/openworkflow-test"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/openworkflow-test"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id = "lt-00000000000000000"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      address            = "openworkflow-test.example.us-east-1.rds.amazonaws.com"
      ca_cert_identifier = "rds-ca-rsa2048-g1"
      master_user_secret = [
        {
          kms_key_id    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
          secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:openworkflow-test"
          secret_status = "active"
        }
      ]
    }
  }
}

mock_provider "random" {}

mock_provider "tls" {}

mock_provider "time" {}

mock_provider "cloudinit" {}

mock_provider "null" {}

run "production_contract" {
  command = plan

  variables {
    name                                 = "openworkflow-test"
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
    cluster_administrator_principal_arns = ["arn:aws:iam::123456789012:role/platform-operators"]
    buckets = {
      backups = {
        expiration_days = 365
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
    condition     = alltrue([for database in aws_db_instance.platform : database.multi_az])
    error_message = "The production contract must enable Multi-AZ RDS."
  }

  assert {
    condition     = alltrue([for database in aws_db_instance.platform : !database.skip_final_snapshot])
    error_message = "The production contract must retain a final RDS snapshot."
  }

  assert {
    condition     = output.database_role_provisioning_required
    error_message = "The handoff must require creation of least-privilege runtime roles."
  }
}
