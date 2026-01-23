# =============================================================================
# STAGING ENVIRONMENT
# =============================================================================

module "app" {
  source = "../../modules/app-stack"

  environment       = "staging"
  project_name      = "demo-app"
  enable_versioning = true

  ssm_parameters = {
    log_level     = "info"
    api_url       = "https://api.staging.example.com"
    feature_flags = "beta"
  }

  tags = {
    Team       = "platform"
    CostCenter = "engineering"
  }
}

# =============================================================================
# STAGING-ONLY: Test data bucket
# =============================================================================

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "test_data" {
  bucket = "staging-demo-app-test-data-${random_id.suffix.hex}"

  tags = {
    Environment = "staging"
    Purpose     = "test-data"
  }
}
