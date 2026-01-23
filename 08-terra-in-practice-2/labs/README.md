# Labs

## Prerequisites

Start LocalStack before running any lab:

```bash
cd ..
docker-compose up -d
```

## Lab 1: Workspaces

Single codebase, multiple state files via `terraform workspace`.

```bash
cd 01-workspaces
terraform init
terraform workspace new dev
terraform apply
```

## Lab 2: Directory Structure

One folder per environment. Shared logic in modules.

```bash
cd 02-directory-structure/environments/dev
terraform init
terraform apply
```

## Lab 3: Terragrunt

DRY configuration with inheritance. Requires Terragrunt installed.

```bash
cd 03-terragrunt/environments/dev
terragrunt init
terragrunt apply
```

## Challenge

After completing all three, try:

1. Add a `qa` environment to Lab 2
2. Modify the module to add a new SSM parameter
3. Compare the effort across approaches
