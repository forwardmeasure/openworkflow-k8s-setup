data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets  = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, index)]
  public_subnets   = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index + 48)]
  database_subnets = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index + 64)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway
  enable_dns_hostnames   = true
  enable_dns_support     = true

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.25.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets

  addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = { before_compute = true }
    aws-ebs-csi-driver = {}
  }

  eks_managed_node_groups = {
    system = {
      instance_types = var.system_instance_types
      min_size       = 3
      desired_size   = 3
      max_size       = 6
      capacity_type  = "ON_DEMAND"
      labels         = { "openworkflow.io/pool" = "system" }
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
    workloads = {
      instance_types = var.workload_instance_types
      min_size       = 3
      desired_size   = 3
      max_size       = 9
      capacity_type  = "ON_DEMAND"
      labels         = { "openworkflow.io/pool" = "workloads" }
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
}

resource "aws_security_group" "postgres" {
  name_prefix = "${var.name}-postgres-"
  description = "PostgreSQL access from EKS workloads"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "random_password" "database" {
  for_each = var.databases
  length   = 32
  special  = false
}

resource "aws_db_instance" "platform" {
  for_each = var.databases

  identifier     = substr("${var.name}-${replace(each.key, "_", "-")}", 0, 63)
  engine         = "postgres"
  engine_version = "17"
  instance_class = each.value.instance_class

  allocated_storage     = each.value.allocated_storage
  max_allocated_storage = each.value.allocated_storage * 5
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = each.value.database_name
  username = each.value.username
  password = random_password.database[each.key].result
  port     = 5432

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = false
  multi_az               = each.value.multi_az

  backup_retention_period    = 14
  backup_window              = "04:00-05:00"
  maintenance_window         = "sun:05:00-sun:06:00"
  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = !var.deletion_protection
  final_snapshot_identifier  = var.deletion_protection ? substr("${var.name}-${replace(each.key, "_", "-")}-final", 0, 63) : null
  copy_tags_to_snapshot      = true
}

resource "aws_s3_bucket" "platform" {
  for_each      = var.buckets
  bucket        = coalesce(each.value.name, trim(substr("${var.name}-${data.aws_caller_identity.current.account_id}-${var.region}-${replace(each.key, "_", "-")}", 0, 63), "-"))
  force_destroy = each.value.force_destroy
  tags          = merge({ Purpose = each.key }, each.value.tags)
}

resource "aws_s3_bucket_public_access_block" "platform" {
  for_each                = aws_s3_bucket.platform
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "platform" {
  for_each = aws_s3_bucket.platform
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "platform" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.platform[each.key].id
  versioning_configuration {
    status = each.value.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "platform" {
  for_each = { for key, value in var.buckets : key => value if value.expiration_days > 0 || value.noncurrent_days > 0 }
  bucket   = aws_s3_bucket.platform[each.key].id

  rule {
    id     = "retention"
    status = "Enabled"
    filter {}
    dynamic "expiration" {
      for_each = each.value.expiration_days > 0 ? [each.value.expiration_days] : []
      content {
        days = expiration.value
      }
    }
    dynamic "noncurrent_version_expiration" {
      for_each = each.value.noncurrent_days > 0 ? [each.value.noncurrent_days] : []
      content {
        noncurrent_days = noncurrent_version_expiration.value
      }
    }
  }
}
