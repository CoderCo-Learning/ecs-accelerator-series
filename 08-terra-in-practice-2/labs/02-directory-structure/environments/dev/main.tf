# =============================================================================
# DEV ENVIRONMENT
# =============================================================================

module "app" {
  source = "../../modules/app-stack"

  environment       = "dev"
  project_name      = "demo-app"
  enable_versioning = false

  ssm_parameters = {
    log_level     = "debug"
    api_url       = "https://api.dev.example.com"
    feature_flags = "experimental,debug_mode"
  }

  tags = {
    Team       = "platform"
    CostCenter = "engineering"
  }
}
