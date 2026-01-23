# =============================================================================
# DEV ENVIRONMENT
# =============================================================================
# Notice how minimal this is - just include + inputs

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/app-stack"
}

inputs = {
  environment       = "dev"
  enable_versioning = false

  ssm_parameters = {
    log_level     = "debug"
    api_url       = "https://api.dev.example.com"
    feature_flags = "experimental,debug_mode"
  }

  tags = {
    Environment = "dev"
    Team        = "platform"
  }
}
