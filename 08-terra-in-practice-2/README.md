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
│             │ + Test data │ + Audit bucket          │
│             │   bucket    │ + Backup bucket         │
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
docker-compose up -d

# Wait a few seconds, then verify
curl http://localhost:4566/_localstack/health

# 2. Navigate to a lab and follow along
cd labs/01-workspaces
terraform init
```

---

## A Note on LocalStack vs Real AWS

In this demo, we're using **LocalStack** – a local AWS emulator. All three environments (dev, staging, prod) run against the same LocalStack instance, which is like using the **same AWS account**.

**Why doesn't this cause conflicts?**

Each environment uses a **name prefix** to avoid collisions:

```
Dev bucket:     dev-demo-app-905e3452
Staging bucket: staging-demo-app-3d0cad06
Prod bucket:    prod-demo-app-9ce8102d
```

**In the real world**, you'd typically use **separate AWS accounts** per environment for proper isolation:

```hcl
# environments/dev/providers.tf
provider "aws" {
  region  = "eu-west-2"
  profile = "dev-account"
}

# environments/prod/providers.tf
provider "aws" {
  region  = "eu-west-2"
  profile = "prod-account"  # Different account!
}
```

The **directory structure pattern works either way** – same account with prefixes, or separate accounts. That's the power: each folder can have completely different provider configs.

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

Run `terraform workspace show` to check – but you have to remember to do it.

**When to use:** Solo dev, prototyping, ephemeral PR environments.

**When to avoid:** Teams > 2-3 people, production workloads.

→ See `labs/01-workspaces/README.md` for full walkthrough.

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
    │   ├── main.tf
    │   └── providers.tf
    │
    ├── staging/             ← Has test_data bucket
    │   ├── main.tf
    │   └── providers.tf
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
  bucket = "prod-audit-logs-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "backups" {
  bucket = "prod-backups-${random_id.suffix.hex}"
}
```

**Why it's better:**

```bash
# Workspaces - silent, easy to forget which one you're in
terraform workspace select prod

# Directory structure - your terminal prompt tells you
~/environments/prod $ terraform apply

# Run pwd - you always know where you are
pwd
/home/user/environments/prod
```

**The "duplication" is a feature:**

- Each environment is self-contained
- Prod can have different provider settings (different account, region)
- Git diff shows exactly what changed per environment
- No inheritance chains to debug on-call. 

**Divergence is natural:**

- Need extra resources in prod? Just add them to `environments/prod/main.tf`
- No awkward `count = terraform.workspace == "prod" ? 1 : 0`

**When to use:** Most teams. This is the default recommendation.

→ See `labs/02-directory-structure/README.md` for full walkthrough.

---

## Approach 3: Terragrunt

**Concept:** DRY configuration with inheritance. Define once, inherit everywhere.

```
03-terragrunt/
├── terragrunt.hcl           ← Root config (generates provider.tf)
│
├── modules/
│   └── app-stack/
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
| Directory | 3-4 files | ~60 lines |
| Terragrunt | 1 file | ~25 lines |

**Power feature – deploy everything at once:**

```bash
cd environments
terragrunt run-all apply --terragrunt-non-interactive
# Deploys dev, staging, prod in one command
```

**When to use:** 10+ environments, complex dependencies between stacks, multiple AWS accounts.

**When to avoid:** Learning Terraform (learn native first), small teams, simple infrastructure.

→ See `labs/03-terragrunt/README.md` for full walkthrough.

---

## Comparison Summary

| Aspect | Workspaces | Directory | Terragrunt |
|--------|------------|-----------|------------|
| State visibility | Hidden in `.d/` | Explicit per folder | Explicit per folder |
| Switch environments | `workspace select` | `cd environments/X` | `cd environments/X` |
| Know where you are | Run `workspace show` | Look at your prompt | Look at your prompt |
| Environment divergence | Awkward (`count = x ? 1 : 0`) | Natural (add resources) | Natural |
| CI/CD setup | Set workspace variable | Set working directory | Set working directory |
| Risk of wrong env | **High** | Low | Low |
| Learning curve | None | None | Medium |
| DRYness | Medium | Low | High |
| Best for | Prototyping | Most teams | Large orgs |

---

## What Gets Created

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| S3 app bucket | ✓ | ✓ | ✓ |
| S3 bucket versioning | ✗ | ✓ | ✓ |
| IAM role + policy | ✓ | ✓ | ✓ |
| SSM parameters | 3 | 3 | 3 |
| S3 test data bucket | ✗ | ✓ | ✗ |
| S3 audit logs bucket | ✗ | ✗ | ✓ |
| S3 backups bucket | ✗ | ✗ | ✓ |

**Environment-specific config:**

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| `versioning` | false | true | true |
| `log_level` | debug | info | warn |
| `log_retention` | 7 days | 30 days | 90 days |

---

## Full Lab Commands

### Lab 1: Workspaces

```bash
cd labs/01-workspaces
terraform init

# Create and deploy DEV
terraform workspace new dev
terraform apply -auto-approve
terraform output

# Create and deploy STAGING
terraform workspace new staging
terraform apply -auto-approve
terraform output

# Create and deploy PROD
terraform workspace new prod
terraform apply -auto-approve
terraform output

# The danger - which workspace are you in?
terraform workspace list
terraform workspace show

# Cleanup
terraform workspace select dev && terraform destroy -auto-approve
terraform workspace select staging && terraform destroy -auto-approve
terraform workspace select prod && terraform destroy -auto-approve
```

### Lab 2: Directory Structure

```bash
# Deploy DEV
cd labs/02-directory-structure/environments/dev
terraform init
terraform apply -auto-approve
terraform output

# Deploy STAGING
cd ../staging
terraform init
terraform apply -auto-approve
terraform output

# Deploy PROD (has extra resources)
cd ../prod
terraform init
terraform apply -auto-approve
terraform output
terraform state list  # See the extra buckets

# Key point - you always know where you are
pwd

# Cleanup
cd ../dev && terraform destroy -auto-approve
cd ../staging && terraform destroy -auto-approve
cd ../prod && terraform destroy -auto-approve
```

### Lab 3: Terragrunt

```bash
# Deploy DEV
cd labs/03-terragrunt/environments/dev
terragrunt init
terragrunt apply -auto-approve
terragrunt output

# Check what got generated
ls -la  # See provider.tf and backend.tf

# Deploy ALL at once
cd ..
terragrunt run-all apply --terragrunt-non-interactive

# Cleanup
terragrunt run-all destroy --terragrunt-non-interactive
```

---

## Prerequisites

- Docker + Docker Compose
- Terraform >= 1.0
- Terragrunt (for Lab 3 only)

**Install Terragrunt (macOS):**

```bash
brew install terragrunt
```

**Install Terragrunt (Linux):**

```bash
curl -LO https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
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