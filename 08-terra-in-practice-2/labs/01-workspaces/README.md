# Lab 1: Terraform Workspaces

## Overview

One codebase, multiple state files. Switch environments with `terraform workspace select`.

## Commands

```bash 
# Initialise
terraform init

# Create workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# List workspaces
terraform workspace list

# Switch workspace
terraform workspace select dev

# Check current workspace
terraform workspace show

# Deploy
terraform plan
terraform apply

# View outputs
terraform output
```

## Try This

1. Deploy to all three environments
2. Compare the outputs between dev and prod
3. Notice the logs bucket only exists in staging/prod

## The Problem

Run this and think about it:

```bash
terraform workspace select prod
# ... do other work ...
# ... come back tomorrow ...
terraform apply  # Which environment?
```

## Cleanup

```bash
terraform workspace select dev && terraform destroy -auto-approve
terraform workspace select staging && terraform destroy -auto-approve
terraform workspace select prod && terraform destroy -auto-approve
```
