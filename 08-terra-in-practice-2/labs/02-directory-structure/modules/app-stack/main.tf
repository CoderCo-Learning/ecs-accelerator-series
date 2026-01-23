# =============================================================================
# APP STACK MODULE
# =============================================================================
# Environment-agnostic module. Receives config via variables.

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "app" {
  bucket = "${var.environment}-${var.project_name}-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    Name        = "${var.environment}-${var.project_name}"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# IAM Role
# -----------------------------------------------------------------------------

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
  name               = "${var.environment}-${var.project_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, {
    Environment = var.environment
  })
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

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:*:*:parameter/${var.environment}/${var.project_name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.environment}-${var.project_name}-policy"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_permissions.json
}

# -----------------------------------------------------------------------------
# SSM Parameters
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "config" {
  for_each = var.ssm_parameters

  name  = "/${var.environment}/${var.project_name}/${each.key}"
  type  = "String"
  value = each.value

  tags = merge(var.tags, {
    Environment = var.environment
  })
}
