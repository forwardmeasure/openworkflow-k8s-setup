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
  enable_cluster_creator_admin_permissions = false
  deletion_protection                      = var.deletion_protection
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets

  access_entries = {
    for principal_arn in var.cluster_administrator_principal_arns : replace(principal_arn, "/", "-") => {
      principal_arn = principal_arn
      policy_associations = {
        administrator = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

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

resource "random_password" "database_runtime" {
  for_each = var.databases
  length   = 40
  special  = false
}

resource "random_id" "final_snapshot" {
  for_each    = var.databases
  byte_length = 4
}

resource "aws_db_parameter_group" "platform" {
  for_each = var.databases

  name_prefix = "${var.name}-${replace(each.key, "_", "-")}-"
  family      = "postgres17"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }
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

  db_name                     = each.value.database_name
  username                    = each.value.administrator_username
  manage_master_user_password = true
  port                        = 5432

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  parameter_group_name   = aws_db_parameter_group.platform[each.key].name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = false
  multi_az               = each.value.multi_az

  backup_retention_period    = 14
  backup_window              = "04:00-05:00"
  maintenance_window         = "sun:05:00-sun:06:00"
  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : substr("${var.name}-${replace(each.key, "_", "-")}-final-${random_id.final_snapshot[each.key].hex}", 0, 63)
  copy_tags_to_snapshot      = true
}

resource "aws_s3_bucket" "platform" {
  for_each      = var.buckets
  bucket        = coalesce(each.value.name, trim(substr("${var.name}-${data.aws_caller_identity.current.account_id}-${var.region}-${replace(each.key, "_", "-")}", 0, 63), "-"))
  force_destroy = each.value.force_destroy
  tags          = merge({ Purpose = each.key }, each.value.tags)
}

resource "aws_secretsmanager_secret" "database_runtime" {
  for_each = var.databases

  name                    = "${var.name}/${replace(each.key, "_", "-")}/runtime"
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "database_runtime" {
  for_each = var.databases

  secret_id     = aws_secretsmanager_secret.database_runtime[each.key].id
  secret_string = random_password.database_runtime[each.key].result
}

resource "aws_s3_bucket_public_access_block" "platform" {
  for_each                = aws_s3_bucket.platform
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "bucket_tls" {
  for_each = aws_s3_bucket.platform

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls" {
  for_each = aws_s3_bucket.platform

  bucket = each.value.id
  policy = data.aws_iam_policy_document.bucket_tls[each.key].json
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

resource "aws_vpc_endpoint" "s3" {
  count = length(var.buckets) > 0 ? 1 : 0

  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

data "aws_iam_policy_document" "workload_assume_role" {
  for_each = var.workload_identities

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = var.workload_identities

  name               = substr("${var.name}-${replace(each.key, "_", "-")}", 0, 64)
  assume_role_policy = data.aws_iam_policy_document.workload_assume_role[each.key].json
}

data "aws_iam_policy_document" "workload_bucket" {
  for_each = { for key, value in var.workload_identities : key => value if length(value.bucket_keys) > 0 }

  statement {
    sid       = "ListBuckets"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
    resources = [for key in each.value.bucket_keys : aws_s3_bucket.platform[key].arn]
  }
  statement {
    sid     = "ManageObjects"
    effect  = "Allow"
    actions = ["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:GetObject", "s3:ListMultipartUploadParts", "s3:PutObject"]
    resources = [
      for key in each.value.bucket_keys : "${aws_s3_bucket.platform[key].arn}/*"
    ]
  }
}

resource "aws_iam_policy" "workload_bucket" {
  for_each = data.aws_iam_policy_document.workload_bucket

  name   = substr("${var.name}-${replace(each.key, "_", "-")}-object-storage", 0, 128)
  policy = each.value.json
}

resource "aws_iam_role_policy_attachment" "workload_bucket" {
  for_each = aws_iam_policy.workload_bucket

  role       = aws_iam_role.workload[each.key].name
  policy_arn = each.value.arn
}

data "aws_iam_policy_document" "workload_database_secret" {
  for_each = {
    for key, value in var.workload_identities : key => value
    if length(value.administrator_database_keys) > 0 || length(value.runtime_database_keys) > 0
  }

  statement {
    sid     = "ReadDatabaseCredentials"
    effect  = "Allow"
    actions = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
    resources = concat(
      [
        for key in each.value.administrator_database_keys : aws_db_instance.platform[key].master_user_secret[0].secret_arn
      ],
      [
        for key in each.value.runtime_database_keys : aws_secretsmanager_secret.database_runtime[key].arn
      ]
    )
  }
}

resource "aws_iam_policy" "workload_database_secret" {
  for_each = data.aws_iam_policy_document.workload_database_secret

  name   = substr("${var.name}-${replace(each.key, "_", "-")}-database-secrets", 0, 128)
  policy = each.value.json
}

resource "aws_iam_role_policy_attachment" "workload_database_secret" {
  for_each = aws_iam_policy.workload_database_secret

  role       = aws_iam_role.workload[each.key].name
  policy_arn = each.value.arn
}

check "database_names_are_unique" {
  assert {
    condition     = length(distinct([for database in values(var.databases) : database.database_name])) == length(var.databases)
    error_message = "Each logical database must have a unique PostgreSQL database name."
  }
}

check "database_runtime_users_are_unique" {
  assert {
    condition     = length(distinct([for database in values(var.databases) : database.runtime_username])) == length(var.databases)
    error_message = "Each logical database must have a unique runtime username."
  }
}

check "workload_bucket_keys_exist" {
  assert {
    condition = alltrue(flatten([
      for identity in values(var.workload_identities) : [
        for bucket_key in identity.bucket_keys : contains(keys(var.buckets), bucket_key)
      ]
    ]))
    error_message = "Every workload identity bucket key must identify a declared bucket."
  }
}

check "workload_database_keys_exist" {
  assert {
    condition = alltrue(flatten([
      for identity in values(var.workload_identities) : [
        for database_key in setunion(identity.administrator_database_keys, identity.runtime_database_keys) : contains(keys(var.databases), database_key)
      ]
    ]))
    error_message = "Every workload identity database key must identify a declared database."
  }
}
