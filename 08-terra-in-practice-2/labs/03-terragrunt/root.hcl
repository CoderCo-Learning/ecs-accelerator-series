# =============================================================================
# ROOT TERRAGRUNT CONFIG
# =============================================================================
# All child terragrunt.hcl files inherit from this.

# -----------------------------------------------------------------------------
# Generate Provider Configuration
# -----------------------------------------------------------------------------
# This creates provider.tf in each environment directory automatically.

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.0"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
        random = {
          source  = "hashicorp/random"
          version = "~> 3.0"
        }
      }
    }

    provider "aws" {
      access_key = "test"
      secret_key = "test"
      region     = "eu-west-2"

      s3_use_path_style           = true
      skip_credentials_validation = true
      skip_metadata_api_check     = true
      skip_requesting_account_id  = true

      endpoints {
        s3  = "http://localhost:4566"
        iam = "http://localhost:4566"
        sts = "http://localhost:4566"
        ssm = "http://localhost:4566"
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Generate Backend Configuration
# -----------------------------------------------------------------------------
# Using local state for this demo. In production, use S3.

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      backend "local" {
        path = "terraform.tfstate"
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Plugin Cache
# -----------------------------------------------------------------------------
# Share provider plugins across all environments to speed up init.

terraform {
  before_hook "create_plugin_cache" {
    commands = ["init"]
    execute  = ["mkdir", "-p", "${get_parent_terragrunt_dir()}/.terraform-plugin-cache"]
  }

  extra_arguments "plugin_cache" {
    commands = ["init", "plan", "apply", "destroy"]
    
    env_vars = {
      TF_PLUGIN_CACHE_DIR = "${get_parent_terragrunt_dir()}/.terraform-plugin-cache"
    }
  }

  extra_arguments "auto_approve" {
    commands = ["apply", "destroy"]
    arguments = ["-auto-approve"]
  }
}

# -----------------------------------------------------------------------------
# Common Inputs
# -----------------------------------------------------------------------------
# These are passed to all modules. Child configs can override.

inputs = {
  project_name = "demo-app"
  tags = {
    ManagedBy = "terragrunt"
  }
}
