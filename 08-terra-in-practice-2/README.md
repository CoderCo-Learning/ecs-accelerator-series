# Terraform Environment Separation

Three approaches to managing dev, staging, and prod with Terraform.

---

## The Problem

You have the same infrastructure across multiple environments:

```
┌─────────────────────────────────────────────────────┐
│                 Same Infrastructure                  │
├─────────────┬─────────────┬─────────────────────────┤
│     Dev     │   Staging   │          Prod           │
├─────────────┼─────────────┼─────────────────────────┤
│ S3 bucket   │ S3 bucket   │ S3 bucket               │
│ IAM role    │ IAM role    │ IAM role                │
│ SSM params  │ SSM params  │ SSM params              │
│             │             │ + Audit bucket          │
│             │             │ + Backup bucket         │
└─────────────┴─────────────┴─────────────────────────┘
```

**Four questions every team faces:**

1. How do you avoid copy-pasting the same config 3 times?
2. How do you handle divergence – prod has extra resources?
3. How do you prevent mistakes – applying dev changes to prod?
4. How do you scale to 10, 20, 50 environments?

---

## The Three Approaches

| Approach | Best For | Risk Level | Complexity |
|----------|----------|------------|------------|
| **Workspaces** | Prototyping, solo dev | High | Low |
| **Directory Structure** | Most teams | Low | Medium |
| **Terragrunt** | Large orgs, 10+ envs | Low | High |

---

## Quick Start

```bash
# 1. Start LocalStack
make setup

# 2. Run any demo
make demo-ws      # Workspaces demo
make demo-dir     # Directory structure demo
make demo-tg      # Terragrunt demo

# 3. Clean up
make teardown
```

Run `make help` to see all available commands.

---

## Approach 1: Workspaces

**Concept:** One codebase, multiple state files. Switch with `terraform workspace select`.

```
Your Code (single folder)
        │
        ▼
   terraform.tfstate.d/
   ├── dev/
   │   └── terraform.tfstate
   ├── staging/
   │   └── terraform.tfstate
   └── prod/
       └── terraform.tfstate
```

**How it works:**

```hcl
# Access workspace name anywhere
resource "aws_s3_bucket" "app" {
  bucket = "${terraform.workspace}-my-app"
}

# Environment-specific values
locals {
  config = {
    dev  = { versioning = false, log_level = "debug" }
    prod = { versioning = true,  log_level = "warn" }
  }
  
  current = local.config[terraform.workspace]
}
```

**The danger:**

```bash
terraform workspace select prod
# ... do other work, come back tomorrow ...
terraform apply  # Which environment? No visual indicator!
```

**When to use:** Solo dev, prototyping, ephemeral PR environments.

**When to avoid:** Teams > 2-3 people, production workloads.

→ See `labs/01-workspaces/` for the full example.

---

## Approach 2: Directory Structure (Recommended)

**Concept:** One folder per environment. Shared logic in modules.

```
02-directory-structure/
├── modules/
│   └── app-stack/           ← Write once, use everywhere
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── environments/
    ├── dev/                 ← cd here = you're in dev
    │   ├── main.tf          ← Calls the module
    │   └── providers.tf
    │
    ├── staging/
    │
    └── prod/                ← Has EXTRA resources
        ├── main.tf          ← Module + audit + backup buckets
        └── providers.tf
```

**How it works:**

```hcl
# environments/dev/main.tf
module "app" {
  source = "../../modules/app-stack"
  
  environment       = "dev"
  enable_versioning = false
}

# environments/prod/main.tf
module "app" {
  source = "../../modules/app-stack"
  
  environment       = "prod"
  enable_versioning = true
}

# Prod-only resources - just add them here
resource "aws_s3_bucket" "audit_logs" {
  bucket = "prod-audit-logs"
}
```

**Why it's better:**

```bash
# Workspaces - silent, easy to forget
terraform workspace select prod

# Directory structure - your prompt tells you
~/environments/prod $ terraform apply
```

**The "duplication" is a feature:**
- Each environment is self-contained
- Prod can have different provider settings
- Git diff shows exactly what changed per environment
- No inheritance chains to debug at 2am

**When to use:** Most teams. This is the default recommendation.

→ See `labs/02-directory-structure/` for the full example.

---

## Approach 3: Terragrunt

**Concept:** DRY configuration with inheritance. Define once, inherit everywhere.

```
03-terragrunt/
├── terragrunt.hcl           ← Root config (generates provider.tf)
│
└── environments/
    ├── dev/
    │   └── terragrunt.hcl   ← Just ~25 lines of inputs
    ├── staging/
    │   └── terragrunt.hcl
    └── prod/
        └── terragrunt.hcl
```

**How it works:**

```hcl
# Root terragrunt.hcl - shared by all
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
    provider "aws" {
      region = "eu-west-2"
    }
  EOF
}

# environments/dev/terragrunt.hcl - minimal!
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/app-stack"
}

inputs = {
  environment       = "dev"
  enable_versioning = false
}
```

**File count comparison:**

| Approach | Files per env | Lines per env |
|----------|---------------|---------------|
| Directory | 4-5 files | ~100 lines |
| Terragrunt | 1 file | ~25 lines |

**Power feature - deploy everything:**

```bash
cd environments
terragrunt run-all apply  # Deploys dev, staging, prod in parallel
```

**When to use:** 10+ environments, complex dependencies, multiple accounts.

**When to avoid:** Learning Terraform, small teams, simple infrastructure.

→ See `labs/03-terragrunt/` for the full example.

---

## Comparison

| Aspect | Workspaces | Directory | Terragrunt |
|--------|------------|-----------|------------|
| State visibility | Hidden in `.d/` | Explicit per folder | Explicit per folder |
| Switch environments | `workspace select` | `cd environments/X` | `cd environments/X` |
| Environment divergence | Awkward (`count = x ? 1 : 0`) | Natural (add resources) | Natural |
| CI/CD | Set workspace variable | Set working directory | Set working directory |
| Risk of wrong env | **High** | Low | Low |
| Learning curve | None | None | Medium |
| Best for | Prototyping | Most teams | Large orgs |

---

## What We're Building

Each approach deploys the same "app stack":

- **S3 bucket** - App storage with environment-specific versioning
- **IAM role + policy** - App permissions for S3 and SSM access
- **SSM parameters** - Environment-specific config (log_level, api_url, etc.)

Plus environment-specific extras:
- **Staging:** Test data bucket
- **Prod:** Audit logs bucket + Backup bucket

---

## Prerequisites

- Docker + Docker Compose
- Terraform >= 1.0
- Terragrunt (for Lab 3 only)

**Install Terragrunt:**

```bash
# macOS
brew install terragrunt

# Linux
curl -LO https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
```

---

## Makefile Commands

```bash
make help           # Show all commands

# Setup
make setup          # Start LocalStack
make teardown       # Stop LocalStack
make clean          # Remove all state files

# Lab 1: Workspaces
make ws-init        # Create all workspaces
make ws-dev         # Deploy dev
make ws-prod        # Deploy prod
make ws-list        # Show workspaces
make ws-destroy     # Destroy all

# Lab 2: Directory Structure  
make dir-dev        # Deploy dev
make dir-prod       # Deploy prod
make dir-all        # Deploy all
make dir-destroy    # Destroy all

# Lab 3: Terragrunt
make tg-dev         # Deploy dev
make tg-prod        # Deploy prod
make tg-all         # Deploy all (run-all)
make tg-destroy     # Destroy all
```

---

## Recommendation

**For 90% of teams: Directory Structure.**

It's explicit, auditable, works with any CI/CD, and naturally handles divergence.

Start there. Move to Terragrunt when you feel the pain of managing 10+ environments.

Use workspaces only for prototyping or ephemeral PR environments.

---

## Resources

- [Terraform Workspaces Docs](https://developer.hashicorp.com/terraform/language/state/workspaces)
- [Terragrunt Docs](https://terragrunt.gruntwork.io/docs/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)