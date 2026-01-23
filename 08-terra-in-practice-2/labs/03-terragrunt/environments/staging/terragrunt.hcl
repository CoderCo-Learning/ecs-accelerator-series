# =============================================================================
# STAGING ENVIRONMENT
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/app-stack"
}

inputs = {
  environment       = "staging"
  enable_versioning = true

  ssm_parameters = {
    log_level     = "info"
    api_url       = "https://api.staging.example.com"
    feature_flags = "beta"
  }

  tags = {
    Environment = "staging"
    Team        = "platform"
  }
}
