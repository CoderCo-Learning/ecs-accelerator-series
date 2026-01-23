# =============================================================================
# PRODUCTION ENVIRONMENT
# =============================================================================

module "app" {
  source = "../../modules/app-stack"

  environment       = "prod"
  project_name      = "demo-app"
  enable_versioning = true

  ssm_parameters = {
    log_level     = "warn"
    api_url       = "https://api.example.com"
    feature_flags = ""
    rate_limit    = "1000"
    cache_ttl     = "3600"
  }

  tags = {
    Team        = "platform"
    CostCenter  = "engineering"
    Criticality = "high"
  }
}

# =============================================================================
# PROD-ONLY RESOURCES
# =============================================================================
# These don't exist in dev or staging

resource "random_id" "suffix" {
  byte_length = 4
}

# Audit logs bucket - compliance requirement
resource "aws_s3_bucket" "audit_logs" {
  bucket = "prod-demo-app-audit-${random_id.suffix.hex}"

  tags = {
    Environment = "prod"
    Purpose     = "audit-logs"
    Compliance  = "required"
  }
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Backup bucket
resource "aws_s3_bucket" "backups" {
  bucket = "prod-demo-app-backups-${random_id.suffix.hex}"

  tags = {
    Environment = "prod"
    Purpose     = "backups"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Additional IAM permissions for audit
data "aws_iam_policy_document" "audit_write" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit_logs.arn}/*"]
  }
}

resource "aws_iam_role_policy" "audit_write" {
  name   = "prod-demo-app-audit-write"
  role   = module.app.iam_role_name
  policy = data.aws_iam_policy_document.audit_write.json
}
