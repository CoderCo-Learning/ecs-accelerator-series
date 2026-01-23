# =============================================================================
# PRODUCTION ENVIRONMENT
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/app-stack"
}

inputs = {
  environment       = "prod"
  enable_versioning = true

  ssm_parameters = {
    log_level     = "warn"
    api_url       = "https://api.example.com"
    feature_flags = "none"
    rate_limit    = "1000"
    cache_ttl     = "3600"
  }

  tags = {
    Environment = "prod"
    Team        = "platform"
    Criticality = "high"
  }
}
