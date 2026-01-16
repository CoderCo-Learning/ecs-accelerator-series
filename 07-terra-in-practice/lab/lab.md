# Lab: Multi-Environment ECS with Terraform

Build a production-ready Terraform setup with remote state, modules and environment separation.

---

## What You'll Build

```
lab/
├── bootstrap/
│   └── main.tf                 # State infrastructure
├── modules/
│   └── ecs-service/
│       ├── main.tf             # ECS resources
│       ├── variables.tf        # Module inputs
│       ├── outputs.tf          # Module outputs
│       └── versions.tf         # Provider constraints
└── environments/
    ├── dev/
    │   ├── main.tf             # Dev environment
    │   ├── backend.tf          # Remote state config
    │   ├── providers.tf        # AWS provider
    │   └── terraform.tfvars    # Dev values
    └── prod/
        ├── main.tf             # Prod environment
        ├── backend.tf          # Remote state config
        ├── providers.tf        # AWS provider
        └── terraform.tfvars    # Prod values
```

---

## Part 1: Bootstrap State Infrastructure

First, create the S3 bucket and DynamoDB table for remote state.

### 1.1 Create Bootstrap Directory

```bash
cd lab/
mkdir -p bootstrap/
cd bootstrap/
```

### 1.2 Create Bootstrap Configuration

**bootstrap/main.tf**

```hcl
terraform {
  required_version = ">= 1.10"  # Required for S3 native locking

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# Generate unique suffix to avoid bucket name conflicts
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "ecs-accelerator-state-${random_id.suffix.hex}"
}

# S3 bucket for state storage
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  tags = {
    Name    = "Terraform State"
    Project = "ecs-accelerator"
  }
}

# Enable versioning for state recovery
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# NOTE: No DynamoDB table needed! 
# Terraform 1.10+ uses S3 native locking with use_lockfile = true

# Output values needed for backend configuration
output "state_bucket" {
  value       = aws_s3_bucket.state.id
  description = "S3 bucket name for terraform state"
}

output "region" {
  value       = "eu-west-2"
  description = "AWS region"
}
```

> **Note:** No DynamoDB table! Terraform 1.10+ uses S3 native locking.

### 1.3 Apply Bootstrap

```bash
terraform init
terraform plan
terraform apply
```

**Note the outputs** – you'll need `state_bucket` and `lock_table` for the next steps.

---

## Part 2: Create the ECS Service Module

This module creates a reusable ECS service pattern.

### 2.1 Create Module Directory

```bash
cd ..
mkdir -p modules/ecs-service
```

### 2.2 Module Versions

**modules/ecs-service/versions.tf**

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### 2.3 Module Variables

**modules/ecs-service/variables.tf**

```hcl
variable "name" {
  type        = string
  description = "Name of the ECS service"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "cluster_id" {
  type        = string
  description = "ECS cluster ID"
}

variable "image" {
  type        = string
  description = "Container image URI"
}

variable "container_port" {
  type        = number
  description = "Port the container listens on"
  default     = 80
}

variable "cpu" {
  type        = number
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  default     = 256
}

variable "memory" {
  type        = number
  description = "Memory in MB for the task"
  default     = 512
}

variable "desired_count" {
  type        = number
  description = "Number of task instances"
  default     = 1
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the service"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the service"
}

variable "assign_public_ip" {
  type        = bool
  description = "Assign public IP to tasks"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
```

### 2.4 Module Main Resources

**modules/ecs-service/main.tf**

```hcl
locals {
  full_name = "${var.environment}-${var.name}"
  
  default_tags = {
    Environment = var.environment
    Service     = var.name
    ManagedBy   = "terraform"
  }
  
  all_tags = merge(local.default_tags, var.tags)
}

# IAM role for task execution (pulling images, writing logs)
resource "aws_iam_role" "execution" {
  name = "${local.full_name}-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.all_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM role for task (application permissions)
resource "aws_iam_role" "task" {
  name = "${local.full_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.all_tags
}

# CloudWatch log group
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.full_name}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = local.all_tags
}

# ECS task definition
resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = var.name
    image = var.image
    
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = var.name
      }
    }

    essential = true
  }])

  tags = local.all_tags
}

# ECS service
resource "aws_ecs_service" "this" {
  name            = local.full_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  # Allow external changes to desired_count (autoscaling)
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.all_tags
}

# Data source for current region
data "aws_region" "current" {}
```

### 2.5 Module Outputs

**modules/ecs-service/outputs.tf**

```hcl
output "service_id" {
  value       = aws_ecs_service.this.id
  description = "ECS service ID"
}

output "service_name" {
  value       = aws_ecs_service.this.name
  description = "ECS service name"
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.this.arn
  description = "Task definition ARN"
}

output "task_role_arn" {
  value       = aws_iam_role.task.arn
  description = "Task IAM role ARN (for adding permissions)"
}

output "execution_role_arn" {
  value       = aws_iam_role.execution.arn
  description = "Execution IAM role ARN"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.this.name
  description = "CloudWatch log group name"
}
```

---

## Part 3: Create Dev Environment

### 3.1 Create Dev Directory

```bash
mkdir -p environments/dev
cd environments/dev
```

### 3.2 Backend Configuration

**environments/dev/backend.tf**

Replace `YOUR_BUCKET_NAME` with the output from bootstrap:

```hcl
terraform {
  backend "s3" {
    bucket       = "YOUR_BUCKET_NAME"  # From bootstrap output
    key          = "ecs-accelerator/dev/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true  # S3 native locking – no DynamoDB!
  }
}
```

### 3.3 Provider Configuration

**environments/dev/providers.tf**

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Project     = "ecs-accelerator"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
```

### 3.4 Main Configuration

**environments/dev/main.tf**

```hcl
locals {
  environment = "dev"
}

# Data source: Get default VPC (for lab simplicity)
data "aws_vpc" "default" {
  default = true
}

# Data source: Get subnets in default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Data source: Current AWS account
data "aws_caller_identity" "current" {}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.environment}-ecs-tasks"
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.environment}-ecs-tasks"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"  # Enable in prod
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE_SPOT"  # Cost savings for dev
  }
}

# API Service using our module
module "api" {
  source = "../../modules/ecs-service"

  name        = "api"
  environment = local.environment
  cluster_id  = aws_ecs_cluster.main.id

  # Using nginx as placeholder – replace with your image
  image          = "nginx:alpine"
  container_port = 80

  cpu    = var.api_cpu
  memory = var.api_memory

  desired_count = var.api_desired_count

  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.ecs_tasks.id]
  assign_public_ip   = true  # Required for Fargate in public subnets

  tags = {
    Component = "api"
  }
}

# Worker Service using our module
module "worker" {
  source = "../../modules/ecs-service"

  name        = "worker"
  environment = local.environment
  cluster_id  = aws_ecs_cluster.main.id

  image          = "nginx:alpine"  # Placeholder
  container_port = 80

  cpu    = var.worker_cpu
  memory = var.worker_memory

  desired_count = var.worker_desired_count

  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.ecs_tasks.id]
  assign_public_ip   = true

  tags = {
    Component = "worker"
  }
}
```

### 3.5 Variables

**environments/dev/variables.tf**

```hcl
variable "api_cpu" {
  type    = number
  default = 256
}

variable "api_memory" {
  type    = number
  default = 512
}

variable "api_desired_count" {
  type    = number
  default = 1
}

variable "worker_cpu" {
  type    = number
  default = 256
}

variable "worker_memory" {
  type    = number
  default = 512
}

variable "worker_desired_count" {
  type    = number
  default = 1
}
```

### 3.6 Environment-Specific Values

**environments/dev/terraform.tfvars**

```hcl
# Dev environment – minimal resources
api_cpu           = 256
api_memory        = 512
api_desired_count = 1

worker_cpu           = 256
worker_memory        = 512
worker_desired_count = 1
```

### 3.7 Outputs

**environments/dev/outputs.tf**

```hcl
output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "api_service_name" {
  value = module.api.service_name
}

output "api_log_group" {
  value = module.api.log_group_name
}

output "worker_service_name" {
  value = module.worker.service_name
}

output "worker_log_group" {
  value = module.worker.log_group_name
}
```

### 3.8 Deploy Dev

```bash
terraform init
terraform plan
terraform apply
```

---

## Part 4: Create Prod Environment

### 4.1 Copy Dev Structure

```bash
cd ..
cp -r dev prod
cd prod
```

### 4.2 Update Backend Key

**environments/prod/backend.tf**

```hcl
terraform {
  backend "s3" {
    bucket       = "YOUR_BUCKET_NAME"  # Same bucket
    key          = "ecs-accelerator/prod/terraform.tfstate"  # Different key!
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

### 4.3 Update Provider Tags

**environments/prod/providers.tf**

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Project     = "ecs-accelerator"
      Environment = "prod"  # Changed
      ManagedBy   = "terraform"
    }
  }
}
```

### 4.4 Update Main Configuration

**environments/prod/main.tf**

Change the local:

```hcl
locals {
  environment = "prod"  # Changed from "dev"
}
```

And update the cluster setting:

```hcl
resource "aws_ecs_cluster" "main" {
  name = "${local.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"  # Enable for prod
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"  # On-demand for prod reliability
  }
}
```

### 4.5 Update Prod Values

**environments/prod/terraform.tfvars**

```hcl
# Prod environment – more resources
api_cpu           = 512
api_memory        = 1024
api_desired_count = 2

worker_cpu           = 512
worker_memory        = 1024
worker_desired_count = 2
```

### 4.6 Deploy Prod

```bash
terraform init
terraform plan
terraform apply
```

---

## Part 5: Verify State Isolation

### 5.1 Check State Files in S3

```bash
aws s3 ls s3://YOUR_BUCKET_NAME/ecs-accelerator/ --recursive
```

You should see:
```
ecs-accelerator/dev/terraform.tfstate
ecs-accelerator/prod/terraform.tfstate
```

### 5.2 Test Locking

Open two terminals. In both, navigate to the same environment:

```bash
cd environments/dev
```

In terminal 1:
```bash
terraform plan
```

While it's running, in terminal 2:
```bash
terraform plan
```

Terminal 2 should show:
```
Acquiring state lock. This may take a few moments...
```

It waits until terminal 1 releases the lock.

### 5.3 Inspect Lock File

While a plan/apply is running, check S3 for the lock file:

```bash
aws s3 ls s3://YOUR_BUCKET_NAME/ecs-accelerator/dev/ 
```

You should see:
```
terraform.tfstate
terraform.tfstate.tflock   # <-- Lock file!
```

The `.tflock` file is deleted when the operation completes.

---

## Part 6: Cleanup

### 6.1 Destroy Prod

```bash
cd environments/prod
terraform destroy
```

### 6.2 Destroy Dev

```bash
cd ../dev
terraform destroy
```

### 6.3 Destroy Bootstrap

```bash
cd ../../bootstrap

# Empty the S3 bucket first (required for deletion)
aws s3 rm s3://YOUR_BUCKET_NAME --recursive

terraform destroy
```

---

## Part 7: LocalStack Lab (No AWS Account Required)

Run the entire lab locally using LocalStack. Perfect for learning without AWS costs.

### 7.1 Prerequisites

```bash
# Install LocalStack
pip install localstack

# Install tflocal wrapper
pip install terraform-local

# Start LocalStack
docker run --rm -d \
  --name localstack \
  -p 4566:4566 \
  -e SERVICES=s3,ecs,ec2,iam,logs,sts \
  localstack/localstack
```

### 7.2 Create LocalStack Configuration

Create a new directory for the LocalStack lab:

```bash
mkdir -p localstack-lab
cd localstack-lab
```

**localstack-lab/main.tf**

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# LocalStack provider configuration
provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3        = "http://localhost:4566"
    ecs       = "http://localhost:4566"
    ec2       = "http://localhost:4566"
    iam       = "http://localhost:4566"
    sts       = "http://localhost:4566"
    cloudwatch = "http://localhost:4566"
    logs      = "http://localhost:4566"
  }
}

# S3 bucket for state (local backend for simplicity)
resource "aws_s3_bucket" "state" {
  bucket = "localstack-terraform-state"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "localstack-cluster"
}

# IAM role for task execution
resource "aws_iam_role" "execution" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# CloudWatch log group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/localstack-demo"
  retention_in_days = 1
}

# ECS Task Definition
resource "aws_ecs_task_definition" "demo" {
  family                   = "localstack-demo"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([{
    name  = "demo"
    image = "nginx:alpine"
    
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = "demo"
      }
    }

    essential = true
  }])
}

output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.demo.arn
}
```

### 7.3 Run with tflocal

The `tflocal` wrapper automatically configures endpoints:

```bash
# Using tflocal (recommended)
tflocal init
tflocal plan
tflocal apply -auto-approve

# Verify resources
aws --endpoint-url=http://localhost:4566 ecs list-clusters
aws --endpoint-url=http://localhost:4566 ecs list-task-definitions
aws --endpoint-url=http://localhost:4566 s3 ls
```

### 7.4 LocalStack with Modules

Create the module structure locally:

```bash
mkdir -p modules/ecs-service
```

**modules/ecs-service/main.tf**

```hcl
variable "name" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "image" {
  type    = string
  default = "nginx:alpine"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 1
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = var.name
    image     = var.image
    essential = true
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = var.name
      }
    }
  }])
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}
```

**localstack-lab/main.tf** (updated to use module)

```hcl
# Add after the cluster resource:

module "api" {
  source = "./modules/ecs-service"

  name       = "api"
  cluster_id = aws_ecs_cluster.main.id
  image      = "nginx:alpine"
}

module "worker" {
  source = "./modules/ecs-service"

  name       = "worker"
  cluster_id = aws_ecs_cluster.main.id
  image      = "nginx:alpine"
}

output "api_task_definition" {
  value = module.api.task_definition_arn
}

output "worker_task_definition" {
  value = module.worker.task_definition_arn
}
```

### 7.5 Cleanup LocalStack

```bash
# Destroy resources
tflocal destroy -auto-approve

# Stop LocalStack
docker stop localstack
```

### LocalStack Limitations

- ECS services don't actually run containers (task definitions work, services are mocked)
- Some IAM policy validations are skipped
- Networking is simulated – no real VPC traffic
- State locking works but uses local file, not S3 conditional writes

**Use LocalStack for:** Learning Terraform syntax, testing module structure, CI pipelines.

**Use real AWS for:** Testing actual ECS behaviour, load balancer configs, networking.

---

## Challenges (Optional)

### Challenge 1: Add SSM Parameter

Add a data source to read an SSM parameter and pass it to the module:

```hcl
data "aws_ssm_parameter" "api_version" {
  name = "/${local.environment}/api/version"
}
```

Create the parameter first:
```bash
aws ssm put-parameter \
  --name "/dev/api/version" \
  --value "1.0.0" \
  --type String
```

### Challenge 2: Add a Staging Environment

Create `environments/staging/` with values between dev and prod.

### Challenge 3: Add ALB to the Module

Extend the module to optionally create an Application Load Balancer:

```hcl
variable "enable_load_balancer" {
  type    = bool
  default = false
}
```

---

## Common Issues

### "Error acquiring state lock"

**For S3 native locking (Terraform 1.10+):**

The lock file is stuck. Delete it manually:

```bash
aws s3 rm s3://YOUR_BUCKET_NAME/ecs-accelerator/dev/terraform.tfstate.tflock
```

**For legacy DynamoDB locking:**

```bash
# Find the lock
aws dynamodb scan --table-name ecs-accelerator-locks

# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### "Backend configuration changed"

```bash
terraform init -reconfigure
```

### "Module not found"

Check the `source` path. Paths are relative to the calling module.

### "No default VPC"

If you deleted your default VPC, create subnets manually and update the data sources.

### "Terraform version too old"

S3 native locking requires Terraform 1.10+. Check your version:

```bash
terraform version
```

---

## Summary

You've built:

- Remote state with S3 native locking (no DynamoDB!)
- A reusable ECS service module
- Separate dev and prod environments
- Data sources referencing existing infrastructure
- LocalStack setup for cost-free local testing

This structure scales to real production use.