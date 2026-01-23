# Labs

## Prerequisites

Start LocalStack before running any lab:

```bash
docker-compose up -d

# Verify it's running
curl http://localhost:4566/_localstack/health
```

---

## Lab 1: Workspaces

Single codebase, multiple state files via `terraform workspace`.

```bash
# Navigate to lab
cd labs/01-workspaces

# Initialise
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

# The danger... which workspace are you in?
terraform workspace list
terraform workspace show

# Compare resources
terraform workspace select dev
terraform state list

terraform workspace select prod
terraform state list
# Notice: prod has aws_s3_bucket.logs[0]

# Cleanup
terraform workspace select dev
terraform destroy -auto-approve

terraform workspace select staging
terraform destroy -auto-approve

terraform workspace select prod
terraform destroy -auto-approve
```

---

## Lab 2: Directory Structure

One folder per environment. Shared logic in modules.

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
# Notice: staging has test_data_bucket

# Deploy PROD
cd ../prod
terraform init
terraform apply -auto-approve
terraform output
terraform state list
# Notice: prod has audit_logs_bucket and backups_bucket

# Key point - you always know where you are
pwd

# Compare resource counts
cd ../dev
terraform state list | wc -l

cd ../prod
terraform state list | wc -l
# Prod has more resources

# Cleanup
cd ../dev
terraform destroy -auto-approve

cd ../staging
terraform destroy -auto-approve

cd ../prod
terraform destroy -auto-approve
```

---

## Lab 3: Terragrunt

DRY configuration with inheritance. Requires Terragrunt installed.

```bash
# Deploy DEV
cd labs/03-terragrunt/environments/dev
terragrunt init
terragrunt apply -auto-approve
terragrunt output

# Check what Terragrunt generated
ls -la
# Notice: provider.tf and backend.tf were auto-generated

# Deploy STAGING
cd ../staging
terragrunt init
terragrunt apply -auto-approve
terragrunt output

# Deploy PROD
cd ../prod
terragrunt init
terragrunt apply -auto-approve
terragrunt output

# Power move - see all outputs at once
cd ..
terragrunt run-all output

# Cleanup - destroy everything in one command
terragrunt run-all destroy --terragrunt-non-interactive
```

---

## Full Cleanup

```bash
# Stop LocalStack
docker-compose down -v

# Remove all Terraform state files (optional)
find . -name "*.tfstate*" -delete
find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null
find . -name ".terraform.lock.hcl" -delete 2>/dev/null
find . -name "terraform.tfstate.d" -type d -exec rm -rf {} + 2>/dev/null
find . -name ".terragrunt-cache" -type d -exec rm -rf {} + 2>/dev/null
```

---

## Challenge

After completing all three labs:

1. Add a `qa` environment to Lab 2 (copy dev folder, change values)
2. Modify the module to add a new SSM parameter
3. Compare the effort across approaches

Which approach would you use for your team?