provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "openworkflow"
      ManagedBy   = "opentofu"
      Environment = var.name
    }
  }
}
