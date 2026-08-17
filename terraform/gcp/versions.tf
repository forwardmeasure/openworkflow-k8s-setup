terraform {
  required_version = ">= 1.8.0"

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
