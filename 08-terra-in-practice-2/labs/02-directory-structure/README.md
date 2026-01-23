# Lab 2: Directory Per Environment

## Overview

Each environment has its own folder with its own state. Shared logic lives in modules.

## Structure

```
02-directory-structure/
├── modules/
│   └── app-stack/        ← Shared module
└── environments/
    ├── dev/              ← cd here for dev
    ├── staging/          ← cd here for staging
    └── prod/             ← cd here for prod (has extra resources)
```

## Commands

```bash
# Deploy dev
cd environments/dev
terraform init
terraform plan
terraform apply

# Deploy staging
cd ../staging
terraform init
terraform apply

# Deploy prod (notice extra resources)
cd ../prod
terraform init
terraform apply
```

## Try This

1. Deploy all three environments
2. Compare `terraform state list` between dev and prod
3. Look at `environments/prod/main.tf` – see the extra audit/backup buckets
4. Add a new environment by copying the dev folder

## Key Insight

Your shell prompt tells you where you are. No workspace confusion.

```bash
~/environments/dev $ terraform apply    # Clearly dev
~/environments/prod $ terraform apply   # Clearly prod
```

## Cleanup

```bash
cd environments/dev && terraform destroy -auto-approve
cd ../staging && terraform destroy -auto-approve
cd ../prod && terraform destroy -auto-approve
```
