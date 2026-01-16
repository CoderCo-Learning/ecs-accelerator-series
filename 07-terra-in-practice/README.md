# Terraform in Practice - Episode 7 of ECS Accelerator Series

This session moves from Terraform basics to production patterns. We cover **remote state**, **modules**, **environment separation** and **data sources**.

---

## Session Objectives

By the end of this session, you will understand:

- Why remote state is required for teams
- How to structure and use modules
- Options for separating environments
- How data sources reference existing infrastructure

---

## Remote State

### The Problem with Local State

Local state works for learning. It fails for teams:

- No locking – concurrent runs corrupt state
- No sharing – each developer has different state
- No backup – lose your laptop, lose your state

### Remote State with S3 (Terraform 1.10+)

As of Terraform 1.10, S3 supports **native state locking** – no DynamoDB required.

```hcl
terraform {
  backend "s3" {
    bucket       = "mycompany-terraform-state"
    key          = "ecs-accelerator/dev/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true  # S3 native locking – no DynamoDB!
  }
}
```

**How it works:**

1. `terraform plan` or `apply` starts
2. Terraform creates a `.tflock` file in S3 using conditional writes
3. If the lock file exists, another process holds the lock – you wait
4. Terraform reads/writes state
5. Terraform deletes the lock file

### Legacy DynamoDB Locking (Pre-1.10)

If you're on older Terraform or have existing DynamoDB infrastructure:

```hcl
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "ecs-accelerator/dev/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"  # old way of locking
  }
}
```

### Migrating from DynamoDB to S3 Native Locking

Enable both temporarily, then remove DynamoDB:

```hcl
# Step 1: Enable both
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"  # Keep during migration
    use_lockfile   = true               # Enable new locking
  }
}

# Step 2: After testing, remove DynamoDB
terraform {
  backend "s3" {
    bucket       = "mycompany-terraform-state"
    key          = "dev/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

### Bootstrap Resources

Remember the egg and chicken problem? This is why we need to bootstrap the resources before we can use them.

The S3 bucket must exist before you use it. For Terraform 1.10+, no DynamoDB needed:

```hcl
resource "aws_s3_bucket" "state" {
  bucket = "mycompany-terraform-state"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

Enable versioning on S3. It lets you recover from state corruption.

---

## Modules

### What is a Module?

A module is a folder containing `.tf` files.

- Your root configuration is a module (the root module)
- When you reference another folder, it becomes a child module
- Modules take inputs (variables) and return outputs

### Module Structure

```
modules/
└── ecs-service/
    ├── main.tf        # Resources
    ├── variables.tf   # Inputs
    ├── outputs.tf     # Return values
    └── versions.tf    # Provider requirements
```

### Defining Module Inputs

This is like your interface to the module. The UI or frontend of the module. This should be clean and easy to understand.

```hcl
# modules/ecs-service/variables.tf
variable "name" {
  type        = string
  description = "Service name"
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "container_port" {
  type = number
}

variable "image" {
  type = string
}
```

### Defining Module Outputs

This is like your return value from the module. The backend of the module.

The outputs are the values that are returned from the module. These are used to reference the module in other modules or in the root module.

```hcl
# modules/ecs-service/outputs.tf
output "service_arn" {
  value = aws_ecs_service.this.arn
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}
```

### Calling a Module

```hcl
module "api" {
  source = "../../modules/ecs-service"

  name           = "api"
  image          = "my-api:latest"
  container_port = 8080
  cpu            = 512
  memory         = 1024
}
```

Reference outputs with `module.api.service_arn`.

### When to Create a Module

Create a module when:

- You have genuine repetition with variation
- You want to enforce standards across teams
- Multiple environments need the same resources

Avoid modules when:

- You only have one instance of something
- You're just trying to organise files
- The "module" would be one or two resources

---

## Environment Separation

### Option 1: Workspaces

Built into Terraform. Same code, different state.

```bash
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
```

```hcl
resource "aws_ecs_cluster" "main" {
  name = "cluster-${terraform.workspace}"
}
```

**Drawback:** Easy to apply to the wrong environment. State is hidden.

### Option 2: Directory per Environment (Recommended, easier but not too complex)

Each environment has its own folder:

```
terraform/
├── modules/
│   └── ecs-service/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
```

**Benefits:**

- Explicit – you know which environment you're in
- Environments can diverge when needed
- Easy to add environment-specific resources

### Option 3: Terragrunt

A wrapper that reduces duplication. Good for large scale. Learn native Terraform first.

---

## Data Sources

Data sources read existing infrastructure. Resources create new infrastructure.

### Look Up Existing VPC

```hcl
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["production-vpc"]
  }
}

resource "aws_subnet" "private" {
  vpc_id = data.aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}
```

### Find Latest AMI

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

### Read SSM Parameter

We don't want to store the password in the Terraform state. This is a security risk. 
Terraform will still store the value in state. Even if it comes from SSM, the secret ends up in the state file.

Best practices:

- Use SSM SecureString
- Lock down S3 state access
- Prefer task role + runtime fetch for high-risk secrets
- Or bootstrap the secret at runtime using the AWS CLI or console and call it via the data source. This is the best way to avoid storing the secret in the state file.

```hcl
data "aws_ssm_parameter" "db_password" {
  name = "/prod/database/password"
}
```

Data sources create dependencies. If the referenced resource doesn't exist, `terraform plan` fails.

---

## Project Structure

Complete layout for multi-environment ECS:

```
terraform/
├── modules/
│   └── ecs-service/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   └── prod/
│       └── (same structure)
└── bootstrap/
    └── main.tf
```

---

## Key Commands

```bash
# Initialise with backend
terraform init

# Migrate local state to remote
terraform init -migrate-state

# Reinitialise with new backend config
terraform init -reconfigure

# Format code
terraform fmt -recursive

# Validate syntax
terraform validate

# Preview changes
terraform plan

# Apply changes
terraform apply

# Destroy all resources
terraform destroy
```

---

## Advanced Techniques

### The `moved` Block (Terraform 1.1+)

Refactor resources without destruction:

```hcl
# Renamed a resource
moved {
  from = aws_instance.old_name
  to   = aws_instance.new_name
}

# Moved into a module
moved {
  from = aws_s3_bucket.logs
  to   = module.logging.aws_s3_bucket.logs
}
```

Use cases: renaming resources, moving into modules, refactoring `count` to `for_each`.

### Import Blocks (Terraform 1.5+)

Import existing resources declaratively:

```hcl
import {
  to = aws_ecs_cluster.existing
  id = "arn:aws:ecs:eu-west-2:123456789:cluster/existing-cluster"
}

resource "aws_ecs_cluster" "existing" {
  name = "existing-cluster"
}
```

### Cross-Stack References

Sometimes you need to reference resources from another Terraform state or something in a different AWS account. This is called a cross-stack reference.

Reference outputs from another Terraform state:

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "mycompany-terraform-state"
    key    = "network/terraform.tfstate"
    region = "eu-west-2"
  }
}

resource "aws_ecs_service" "api" {
  network_configuration {
    subnets = data.terraform_remote_state.network.outputs.private_subnet_ids
  }
}
```

### Useful State Commands

```bash
# List all resources
terraform state list

# Show resource details
terraform state show aws_ecs_cluster.main

# Remove from state (doesn't destroy)
terraform state rm aws_ecs_service.legacy

# Pull state to local file
terraform state pull > state.json
```

---

## Summary

| Concept | Purpose |
|---------|---------|
| Remote State | Shared state with locking for teams |
| `use_lockfile` | S3 native locking (Terraform 1.10+) |
| Modules | Reusable infrastructure components |
| Environments | Separate state per deployment target |
| Data Sources | Reference existing infrastructure |
| `moved` block | Refactor without destroying resources |
| `import` block | Import existing resources declaratively |

---

## Next Session

ECS-specific Terraform patterns:

- Task definition lifecycle
- Service dependencies (ALB → Target Group → Service)
- Secrets management
- Deployment strategies