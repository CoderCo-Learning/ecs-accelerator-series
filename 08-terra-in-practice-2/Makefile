# =============================================================================
# Terraform Environment Separation Demo
# =============================================================================
# Run `make help` to see all available commands

.PHONY: help setup teardown clean
.PHONY: ws-init ws-dev ws-staging ws-prod ws-list ws-destroy
.PHONY: dir-dev dir-staging dir-prod dir-all dir-destroy
.PHONY: tg-dev tg-staging tg-prod tg-all tg-destroy

# -----------------------------------------------------------------------------
# Setup & Teardown
# -----------------------------------------------------------------------------

help: ## Show this help
	@echo ""
	@echo "Terraform Environment Separation Demo"
	@echo "======================================"
	@echo ""
	@echo "SETUP"
	@echo "  make setup          Start LocalStack"
	@echo "  make teardown       Stop LocalStack and clean up"
	@echo "  make clean          Remove all Terraform state files"
	@echo ""
	@echo "LAB 1: WORKSPACES"
	@echo "  make ws-init        Initialise and create workspaces"
	@echo "  make ws-dev         Deploy to dev workspace"
	@echo "  make ws-staging     Deploy to staging workspace"
	@echo "  make ws-prod        Deploy to prod workspace"
	@echo "  make ws-list        List all workspaces and show current"
	@echo "  make ws-destroy     Destroy all workspace resources"
	@echo ""
	@echo "LAB 2: DIRECTORY STRUCTURE"
	@echo "  make dir-dev        Deploy dev environment"
	@echo "  make dir-staging    Deploy staging environment"
	@echo "  make dir-prod       Deploy prod environment"
	@echo "  make dir-all        Deploy all environments"
	@echo "  make dir-destroy    Destroy all environments"
	@echo ""
	@echo "LAB 3: TERRAGRUNT"
	@echo "  make tg-dev         Deploy dev environment"
	@echo "  make tg-staging     Deploy staging environment"
	@echo "  make tg-prod        Deploy prod environment"
	@echo "  make tg-all         Deploy all environments"
	@echo "  make tg-destroy     Destroy all environments"
	@echo ""

setup: ## Start LocalStack
	@echo "Starting LocalStack..."
	docker-compose up -d
	@echo "Waiting for LocalStack to be ready..."
	@sleep 5
	@curl -s http://localhost:4566/_localstack/health | grep -q "running" && echo "LocalStack is ready!" || echo "LocalStack may still be starting..."

teardown: ## Stop LocalStack and clean up
	@echo "Stopping LocalStack..."
	docker-compose down -v
	@echo "Done."

clean: ## Remove all Terraform state and cache files
	@echo "Cleaning up Terraform state files..."
	find . -name "*.tfstate*" -delete
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	find . -name "terraform.tfstate.d" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terragrunt-cache" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "provider.tf" -path "*/03-terragrunt/*" -delete 2>/dev/null || true
	find . -name "backend.tf" -path "*/03-terragrunt/*" -delete 2>/dev/null || true
	@echo "Done."

# -----------------------------------------------------------------------------
# Lab 1: Workspaces
# -----------------------------------------------------------------------------

ws-init: ## Initialise workspaces lab and create all workspaces
	@echo "=== Initialising Workspaces Lab ==="
	cd labs/01-workspaces && terraform init
	cd labs/01-workspaces && terraform workspace new dev 2>/dev/null || true
	cd labs/01-workspaces && terraform workspace new staging 2>/dev/null || true
	cd labs/01-workspaces && terraform workspace new prod 2>/dev/null || true
	@echo ""
	@echo "Workspaces created. Current workspaces:"
	cd labs/01-workspaces && terraform workspace list

ws-dev: ## Deploy to dev workspace
	@echo "=== Deploying to DEV workspace ==="
	cd labs/01-workspaces && terraform workspace select dev
	cd labs/01-workspaces && terraform apply -auto-approve
	@echo ""
	@echo "=== DEV Outputs ==="
	cd labs/01-workspaces && terraform output

ws-staging: ## Deploy to staging workspace
	@echo "=== Deploying to STAGING workspace ==="
	cd labs/01-workspaces && terraform workspace select staging
	cd labs/01-workspaces && terraform apply -auto-approve
	@echo ""
	@echo "=== STAGING Outputs ==="
	cd labs/01-workspaces && terraform output

ws-prod: ## Deploy to prod workspace
	@echo "=== Deploying to PROD workspace ==="
	cd labs/01-workspaces && terraform workspace select prod
	cd labs/01-workspaces && terraform apply -auto-approve
	@echo ""
	@echo "=== PROD Outputs ==="
	cd labs/01-workspaces && terraform output

ws-list: ## List all workspaces and show current
	@echo "=== Workspaces ==="
	cd labs/01-workspaces && terraform workspace list
	@echo ""
	@echo "Current workspace:"
	cd labs/01-workspaces && terraform workspace show

ws-destroy: ## Destroy all workspace resources
	@echo "=== Destroying all workspaces ==="
	cd labs/01-workspaces && terraform workspace select dev && terraform destroy -auto-approve || true
	cd labs/01-workspaces && terraform workspace select staging && terraform destroy -auto-approve || true
	cd labs/01-workspaces && terraform workspace select prod && terraform destroy -auto-approve || true
	@echo "Done."

# -----------------------------------------------------------------------------
# Lab 2: Directory Structure
# -----------------------------------------------------------------------------

dir-dev: ## Deploy dev environment (directory structure)
	@echo "=== Deploying DEV (Directory Structure) ==="
	cd labs/02-directory-structure/environments/dev && terraform init
	cd labs/02-directory-structure/environments/dev && terraform apply -auto-approve
	@echo ""
	@echo "=== DEV Outputs ==="
	cd labs/02-directory-structure/environments/dev && terraform output

dir-staging: ## Deploy staging environment (directory structure)
	@echo "=== Deploying STAGING (Directory Structure) ==="
	cd labs/02-directory-structure/environments/staging && terraform init
	cd labs/02-directory-structure/environments/staging && terraform apply -auto-approve
	@echo ""
	@echo "=== STAGING Outputs ==="
	cd labs/02-directory-structure/environments/staging && terraform output

dir-prod: ## Deploy prod environment (directory structure)
	@echo "=== Deploying PROD (Directory Structure) ==="
	cd labs/02-directory-structure/environments/prod && terraform init
	cd labs/02-directory-structure/environments/prod && terraform apply -auto-approve
	@echo ""
	@echo "=== PROD Outputs ==="
	cd labs/02-directory-structure/environments/prod && terraform output

dir-all: dir-dev dir-staging dir-prod ## Deploy all environments (directory structure)
	@echo ""
	@echo "=== All environments deployed ==="

dir-destroy: ## Destroy all environments (directory structure)
	@echo "=== Destroying all environments (Directory Structure) ==="
	cd labs/02-directory-structure/environments/dev && terraform destroy -auto-approve || true
	cd labs/02-directory-structure/environments/staging && terraform destroy -auto-approve || true
	cd labs/02-directory-structure/environments/prod && terraform destroy -auto-approve || true
	@echo "Done."

# -----------------------------------------------------------------------------
# Lab 3: Terragrunt
# -----------------------------------------------------------------------------

tg-dev: ## Deploy dev environment (Terragrunt)
	@echo "=== Deploying DEV (Terragrunt) ==="
	cd labs/03-terragrunt/environments/dev && terragrunt init
	cd labs/03-terragrunt/environments/dev && terragrunt apply -auto-approve
	@echo ""
	@echo "=== DEV Outputs ==="
	cd labs/03-terragrunt/environments/dev && terragrunt output

tg-staging: ## Deploy staging environment (Terragrunt)
	@echo "=== Deploying STAGING (Terragrunt) ==="
	cd labs/03-terragrunt/environments/staging && terragrunt init
	cd labs/03-terragrunt/environments/staging && terragrunt apply -auto-approve
	@echo ""
	@echo "=== STAGING Outputs ==="
	cd labs/03-terragrunt/environments/staging && terragrunt output

tg-prod: ## Deploy prod environment (Terragrunt)
	@echo "=== Deploying PROD (Terragrunt) ==="
	cd labs/03-terragrunt/environments/prod && terragrunt init
	cd labs/03-terragrunt/environments/prod && terragrunt apply -auto-approve
	@echo ""
	@echo "=== PROD Outputs ==="
	cd labs/03-terragrunt/environments/prod && terragrunt output

tg-all: ## Deploy all environments (Terragrunt)
	@echo "=== Deploying ALL environments (Terragrunt) ==="
	cd labs/03-terragrunt/environments && terragrunt run-all apply --terragrunt-non-interactive
	@echo "Done."

tg-destroy: ## Destroy all environments (Terragrunt)
	@echo "=== Destroying all environments (Terragrunt) ==="
	cd labs/03-terragrunt/environments && terragrunt run-all destroy --terragrunt-non-interactive
	@echo "Done."

# -----------------------------------------------------------------------------
# Demo Shortcuts
# -----------------------------------------------------------------------------

demo-ws: ws-init ws-dev ws-prod ws-list ## Run full workspaces demo
	@echo ""
	@echo "=== Workspaces Demo Complete ==="
	@echo "Notice: dev and prod have different outputs"
	@echo "The 'logs_bucket' only exists in staging/prod"

demo-dir: dir-dev dir-prod ## Run full directory structure demo
	@echo ""
	@echo "=== Directory Structure Demo Complete ==="
	@echo "Compare: prod has audit_logs_bucket and backups_bucket"

demo-tg: tg-dev tg-prod ## Run full Terragrunt demo
	@echo ""
	@echo "=== Terragrunt Demo Complete ==="
	@echo "Check the generated provider.tf in each environment folder"