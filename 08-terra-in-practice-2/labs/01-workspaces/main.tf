# =============================================================================
# WORKSPACE VALIDATION
# =============================================================================
# Prevent using default workspace or unknown workspaces

locals {
  # Error if using default workspace
  _check_not_default = (
    terraform.workspace == "default"
    ? tobool("ERROR: Don't use default workspace. Run: terraform workspace new dev")
    : true
  )

  # Error if workspace not in allowed list
  _check_valid = (
    contains(var.allowed_workspaces, terraform.workspace)
    ? true
    : tobool("ERROR: Unknown workspace '${terraform.workspace}'")
  )
}

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================
# This is where workspaces shine - same code, different values

locals {
  env_config = {
    dev = {
      bucket_prefix     = "dev"
      enable_versioning = false
      log_retention     = 7
      ssm_params = {
        log_level     = "debug"
        api_url       = "https://api.dev.example.com"
        feature_flags = "experimental,debug_mode"
      }
    }
    staging = {
      bucket_prefix     = "staging"
      enable_versioning = true
      log_retention     = 30
      ssm_params = {
        log_level     = "info"
        api_url       = "https://api.staging.example.com"
        feature_flags = "beta"
      }
    }
    prod = {
      bucket_prefix     = "prod"
      enable_versioning = true
      log_retention     = 90
      ssm_params = {
        log_level     = "warn"
        api_url       = "https://api.example.com"
        feature_flags = "none"
      }
    }
  }

  # Current environment's config
  config = local.env_config[terraform.workspace]
}

# =============================================================================
# RESOURCES
# =============================================================================

resource "random_id" "suffix" {
  byte_length = 4
}

# S3 Bucket - App Storage
resource "aws_s3_bucket" "app" {
  bucket = "${local.config.bucket_prefix}-${var.project_name}-${random_id.suffix.hex}"

  tags = {
    Name        = "${local.config.bucket_prefix}-${var.project_name}"
    Environment = terraform.workspace
    ManagedBy   = "terraform-workspaces"
  }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = local.config.enable_versioning ? "Enabled" : "Disabled"
  }
}

# IAM Role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "app" {
  name               = "${terraform.workspace}-${var.project_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Environment = terraform.workspace
  }
}

data "aws_iam_policy_document" "app_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.app.arn,
      "${aws_s3_bucket.app.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${terraform.workspace}-${var.project_name}-policy"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_permissions.json
}

# SSM Parameters
resource "aws_ssm_parameter" "config" {
  for_each = local.config.ssm_params

  name  = "/${terraform.workspace}/${var.project_name}/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Environment = terraform.workspace
  }
}

# =============================================================================
# CONDITIONAL RESOURCE - Only in staging/prod
# =============================================================================
# This shows the awkwardness of workspaces for divergent environments

resource "aws_s3_bucket" "logs" {
  count = terraform.workspace != "dev" ? 1 : 0

  bucket = "${local.config.bucket_prefix}-${var.project_name}-logs-${random_id.suffix.hex}"

  tags = {
    Name        = "${local.config.bucket_prefix}-${var.project_name}-logs"
    Environment = terraform.workspace
    Purpose     = "access-logs"
  }
}
