region = "us-east-1"
name   = "openworkflow-dev"

cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
single_nat_gateway                   = true
deletion_protection                  = false

buckets = {
  backups = {
    versioning      = true
    expiration_days = 365
    noncurrent_days = 30
  }
}
