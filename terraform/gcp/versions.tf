terraform {
  # 1.11: ephemeral variables and write-only attributes (cloudsql_user_passwords / password_wo).
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.44"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
