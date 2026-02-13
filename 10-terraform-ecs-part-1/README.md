# Episode 10 – Terraform for ECS (Part 1)

## The Journey So Far

```
Episode 1-4:  You learned to containerise
Episode 5:    You pushed to ECR
Episode 6-8:  You learned Terraform foundations
Episode 9:    You deployed ECS manually (ClickOps)
```

Now we destroy what you clicked, and rebuild it as code.

---

## What We're Codifying

| AWS Console | Terraform Resource |
|-------------|-------------------|
| VPC | `aws_vpc` |
| Subnets | `aws_subnet` |
| Internet Gateway | `aws_internet_gateway` |
| NAT Gateway | `aws_nat_gateway` |
| Route Table | `aws_route_table` |
| Security Group | `aws_security_group` |
| ECR Repository | `aws_ecr_repository` |
| ECS Cluster | `aws_ecs_cluster` |
| Task Definition | `aws_ecs_task_definition` |
| IAM Role | `aws_iam_role` |

---

## VPC - Virtual Private Cloud

Your own isolated network inside AWS. Think of AWS as a massive data centre - a VPC is your private section with your own IP range, network rules, and routing decisions.

```
┌─────────────────────────────────────────────────────────┐
│                        AWS Cloud                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │                    Your VPC                        │  │
│  │                  10.0.0.0/22                       │  │
│  │   Your resources live here, isolated from others  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### CIDR Block - Size Matters

The IP range for your VPC. Pick the right size for your project.

| CIDR | IP Addresses | Use Case |
|------|--------------|----------|
| /28 | 16 | Too small - avoid |
| /24 | 256 | Single small app, dev/test |
| /22 | 1,024 | **Small to medium projects** ✓ |
| /20 | 4,096 | Multiple services, room to grow |
| /16 | 65,536 | Enterprise, multi-team platforms |

**🏭 Industry tip:** Don't default to /16. Most projects never use 65,000 IPs. You're wasting address space and making subnet maths harder.

**For your ECS project:** Use `/22` (1,024 IPs). Plenty of room for:
- 4 subnets (/24 each = 256 IPs per subnet)
- ALB, ECS tasks, RDS, future services
- Not wasteful, not cramped

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/22"  # 1,024 IPs - right-sized
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "my-app-vpc"
    Environment = "production"
  }
}
```

### Why enable_dns_hostnames?

- Instances get DNS names (ec2-xx-xx-xx-xx.region.compute.amazonaws.com)
- Required for ECS service discovery
- Required for VPC endpoints
- **Always enable it.** No reason not to.

### VPC Planning Questions

Before creating a VPC, ask:
1. How many services will run here?
2. Will this VPC peer with others? (CIDR must not overlap)
3. Dev/staging/prod - same or separate VPCs?

**🏭 Industry tip:** Most companies use separate VPCs per environment. Blast radius - if someone breaks dev, prod is safe.

---

## Subnets

Subdivisions of your VPC. You carve up your VPC CIDR into smaller networks.

```
┌─────────────────────────────────────────────────────────┐
│                    VPC: 10.0.0.0/22                      │
│                    (1,024 total IPs)                     │
│                                                          │
│   ┌─────────────────┐    ┌─────────────────┐            │
│   │  Public Subnet  │    │  Public Subnet  │            │
│   │  10.0.0.0/25    │    │  10.0.0.128/25  │            │
│   │   (128 IPs)     │    │   (128 IPs)     │            │
│   │     AZ-a        │    │     AZ-b        │            │
│   │  ALB, NAT GW    │    │  ALB            │            │
│   └─────────────────┘    └─────────────────┘            │
│                                                          │
│   ┌─────────────────┐    ┌─────────────────┐            │
│   │ Private Subnet  │    │ Private Subnet  │            │
│   │  10.0.1.0/25    │    │  10.0.1.128/25  │            │
│   │   (128 IPs)     │    │   (128 IPs)     │            │
│   │     AZ-a        │    │     AZ-b        │            │
│   │  ECS Tasks, RDS │    │  ECS Tasks, RDS │            │
│   └─────────────────┘    └─────────────────┘            │
│                                                          │
│   Remaining: 10.0.2.0/24, 10.0.3.0/24 (future use)      │
└─────────────────────────────────────────────────────────┘
```

### Public vs Private - Know the Difference

**Public Subnet:**
- Has route to Internet Gateway
- Resources CAN have public IPs
- Directly reachable from internet (if security group allows)
- Use for: ALB, NAT Gateway, bastion hosts

**Private Subnet:**
- NO direct route to internet
- Resources are hidden from public
- Can reach internet via NAT Gateway (outbound only)
- Use for: ECS tasks, databases, internal services

**🏭 Industry tip:** Put your application in private subnets. Only the ALB should be public. Defence in depth.

### Why Multiple AZs?

High availability. AZs are physically separate data centres.

- If AZ-a has a power outage, AZ-b keeps running
- ALB requires subnets in at least 2 AZs
- RDS Multi-AZ needs subnets in 2 AZs

**For your project:** 2 AZs is enough. 3 AZs if you want extra redundancy (costs more).

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 3, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "public-${count.index + 1}"
    Type = "public"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 3, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "private-${count.index + 1}"
    Type = "private"
  }
}
```

**🏭 Industry tip:** Use `cidrsubnet()` function instead of hardcoding. Change the VPC CIDR once, subnets update automatically.

### Reserved IPs

AWS reserves 5 IPs per subnet:
- .0 - Network address
- .1 - VPC router
- .2 - DNS server
- .3 - Reserved for future
- .255 - Broadcast (not used but reserved)

A /24 subnet (256 IPs) = 251 usable. A /25 (128 IPs) = 123 usable.

---

## Internet Gateway (IGW)

The door between your VPC and the public internet.

```
                    Internet
                        │
                        ▼
              ┌─────────────────┐
              │ Internet Gateway │
              └─────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │   Public Subnet  │
              └─────────────────┘
```

- One IGW per VPC. That's all you need.
- No bandwidth limits, no extra cost
- Fully managed by AWS

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "my-app-igw"
  }
}
```

**🏭 Industry tip:** IGW is free. Don't overcomplicate it.

---

## NAT Gateway

Allows private subnets to reach the internet (outbound only).

Your ECS tasks in private subnets need to:
- Pull Docker images from ECR
- Download packages
- Call external APIs (Stripe, Twilio, etc.)

**NAT Gateway = one-way door.** Private resources go out, nothing comes in uninvited.

```
                    Internet
                        │
                        ▼
              ┌─────────────────┐
              │ Internet Gateway │
              └─────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │   Public Subnet  │
              │   ┌───────────┐  │
              │   │  NAT GW   │  │
              │   └───────────┘  │
              └─────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │  Private Subnet  │
              │   (ECS Tasks)    │
              │  Can reach out   │
              │  Can't be reached│
              └─────────────────┘
```

### Cost Warning ⚠️

NAT Gateway is expensive:
- ~$32/month just to exist
- Plus $0.045/GB data processed

**For dev/staging environments:**
1. Skip NAT Gateway entirely
2. Put Fargate tasks in public subnets
3. Use VPC endpoints for ECR/S3/CloudWatch (no NAT needed for AWS services)

**For production:** Use NAT Gateway. Security > cost.

```hcl
# Only create NAT Gateway for production
resource "aws_eip" "nat" {
  count  = var.environment == "production" ? 1 : 0
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  count         = var.environment == "production" ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]
}
```

**🏭 Industry tip:** One NAT Gateway per AZ for true high availability. But for most projects, one is fine - it's a cost/HA tradeoff.

### VPC Endpoints - The NAT Alternative

For AWS services, use VPC endpoints instead of NAT Gateway:
- ECR (for pulling images)
- S3 (for storing artifacts)
- CloudWatch Logs (for logging)

Free for Gateway endpoints (S3, DynamoDB). ~$7/month for Interface endpoints.

---

## Route Tables

Traffic rules. Tells AWS where to send network traffic.

Every subnet needs a route table. Think of it as the GPS for your network.

### Public Route Table

```
Destination     │ Target
────────────────┼──────────────────
10.0.0.0/22     │ local (within VPC)
0.0.0.0/0       │ igw-xxx (Internet Gateway)
```

"Send VPC traffic locally. Send everything else to the internet."

### Private Route Table

```
Destination     │ Target
────────────────┼──────────────────
10.0.0.0/22     │ local (within VPC)
0.0.0.0/0       │ nat-xxx (NAT Gateway)
```

"Send VPC traffic locally. Send everything else through NAT."

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = { Name = "private-rt" }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

**🏭 Industry tip:** Forgetting route table associations is a common mistake. Subnet without association = uses VPC main route table (which might not have the routes you expect).

---

## Security Groups

Virtual firewall for your resources. Controls inbound and outbound traffic.

### The Golden Rules

1. **Deny by default.** No rules = no traffic.
2. **Least privilege.** Only open what you need.
3. **Reference security groups, not IPs.** Cleaner, more maintainable.
4. **Separate SGs per tier.** ALB SG, ECS SG, RDS SG.

```
┌─────────────────────────────────────────────────────────┐
│                    Traffic Flow                          │
│                                                          │
│  Internet ──► ALB SG (80, 443) ──► ECS SG (app port)    │
│                                          │               │
│                                          ▼               │
│                                    RDS SG (3306)         │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

```hcl
# ALB Security Group - accepts traffic from internet
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

# ECS Security Group - ONLY accepts traffic from ALB
resource "aws_security_group" "ecs" {
  name        = "ecs-tasks-sg"
  description = "ECS tasks security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Traffic from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # Reference SG, not CIDR!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ecs-tasks-sg" }
}
```

**🏭 Industry tip:** Never use `0.0.0.0/0` for ingress on your application security group. If someone bypasses your ALB, they shouldn't be able to hit your app directly.

---

## ECS Deep Dive

### What is ECS?

Elastic Container Service. AWS managed container orchestration.

You tell AWS what containers to run → ECS handles scheduling, scaling, health checks, networking.

Think of it as a hotel manager. You describe the room requirements, the manager assigns rooms and handles housekeeping.

### Fargate vs EC2 Launch Type

| | Fargate | EC2 |
|--|---------|-----|
| Who manages servers? | AWS | You |
| Scaling | Automatic | You configure ASG |
| Pricing | Per task (CPU + memory + time) | Instance cost |
| Best for | Most workloads, simplicity | GPU, specific instances, cost optimisation at scale |

**For your project:** Use Fargate. No servers to patch, no capacity planning.

**🏭 Industry tip:** Start with Fargate. Move to EC2 only if you have a specific reason (GPU, cost at scale, specific instance requirements).

---

## ECS Cluster

Logical grouping of tasks and services. Just a namespace.

```
┌─────────────────────────────────────────┐
│            ECS Cluster                   │
│         "my-app-cluster"                 │
│                                          │
│  ┌─────────────┐  ┌─────────────┐       │
│  │  Service A  │  │  Service B  │       │
│  │  (API)      │  │  (Worker)   │       │
│  │             │  │             │       │
│  │ Task  Task  │  │ Task  Task  │       │
│  └─────────────┘  └─────────────┘       │
└─────────────────────────────────────────┘
```

```hcl
resource "aws_ecs_cluster" "main" {
  name = "my-app-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = var.environment
  }
}
```

**Always enable Container Insights.** Gives you CPU, memory, network metrics per task. Essential for debugging and capacity planning.

---

## Task Definition

The blueprint. Describes HOW to run your container.

### Key Settings Explained

**Family and Revision:**
- Family = name (e.g., "my-app")
- Revision = version (auto-increments)
- Together: `my-app:3`

**Network Mode:**
| Mode | Description | Use When |
|------|-------------|----------|
| awsvpc | Each task gets own ENI | Fargate (required) |
| bridge | Docker bridge | EC2, multiple containers per instance |
| host | Host network | EC2, maximum network performance |

**CPU and Memory (Fargate):**
| CPU | Memory Options | Monthly Cost (approx) |
|-----|----------------|----------------------|
| 256 (.25 vCPU) | 512MB, 1GB, 2GB | ~$9 |
| 512 (.5 vCPU) | 1-4GB | ~$18 |
| 1024 (1 vCPU) | 2-8GB | ~$36 |
| 2048 (2 vCPU) | 4-16GB | ~$72 |

**🏭 Industry tip:** Start with 256 CPU / 512 MB. Monitor actual usage, then right-size. Most APIs don't need 1 vCPU.

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "my-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      { name = "NODE_ENV", value = var.environment }
    ]

    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}
```

### Environment vs Secrets

| | Environment | Secrets |
|--|-------------|---------|
| Stored | Plain text in task def | SSM Parameter Store / Secrets Manager |
| Visible | Yes, in AWS Console | No, fetched at runtime |
| Use for | Non-sensitive config (NODE_ENV, PORT) | Passwords, API keys, tokens |

**🏭 Industry tip:** Never put secrets in environment variables. They're visible in the console, in logs, everywhere. Always use `secrets` with SSM or Secrets Manager.

---

## IAM Roles - Execution vs Task

People confuse these constantly. Know the difference.

```
┌─────────────────────────────────────────────────────────┐
│                                                          │
│   EXECUTION ROLE                    TASK ROLE            │
│   (ECS agent uses this)             (Your app uses this) │
│                                                          │
│   ✓ Pull images from ECR            ✓ Call S3            │
│   ✓ Send logs to CloudWatch         ✓ Call DynamoDB      │
│   ✓ Fetch secrets from SSM          ✓ Call any AWS API   │
│                                                          │
│   Required to START the task        Only if app needs it │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

```hcl
# Execution Role - always needed
resource "aws_iam_role" "ecs_execution" {
  name = "${var.app_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role - only if your app calls AWS APIs
resource "aws_iam_role" "ecs_task" {
  name = "${var.app_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
```

**🏭 Industry tip:** Don't over-permission. If your app only serves HTTP requests, it doesn't need a task role. Add permissions only when the app actually needs to call AWS APIs.

---

## ECR - Elastic Container Registry

AWS managed Docker registry.

### Image Tagging Strategy

**Never use `:latest` in production.**

| Tag Type | Example | Pros | Cons |
|----------|---------|------|------|
| latest | my-app:latest | Easy | Can't track versions, can't rollback |
| Semantic | my-app:v1.2.3 | Clear versioning | Manual tagging |
| Git SHA | my-app:abc123f | Traceable to commit | Not human readable |
| Build ID | my-app:build-456 | CI/CD friendly | Need to look up what's in it |

**🏭 Industry tip:** Use Git SHA + semantic version. Tag as `my-app:abc123f` AND `my-app:v1.2.3`. Best of both worlds.

```hcl
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "IMMUTABLE"  # Prevent tag overwrites

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = var.environment
  }
}

# Clean up old images
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
```

**🏭 Industry tip:** `IMMUTABLE` tags prevent accidents. Once `v1.2.3` exists, you can't push a different image with that tag. Forces proper versioning.

---

## Project Structure

```
ecs-project/
├── main.tf           # Provider, backend config
├── variables.tf      # Input variables
├── outputs.tf        # Outputs (ALB DNS, ECR URL)
├── vpc.tf            # VPC, subnets, IGW, NAT, routes
├── security.tf       # Security groups
├── ecr.tf            # Container registry
├── iam.tf            # IAM roles
├── ecs.tf            # Cluster, task definition, service
├── alb.tf            # Load balancer (Part 2)
├── dns.tf            # Route53, ACM (Part 2)
├── logs.tf           # CloudWatch log groups
├── variables/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
└── README.md
```

---

## Key Takeaways

✅ Right-size your VPC - /22 for small projects, not /16  
✅ Public subnets for ALB, private subnets for application  
✅ NAT Gateway is expensive - skip for dev, use VPC endpoints  
✅ Security groups: least privilege, reference SGs not CIDRs  
✅ Start small with Fargate (256 CPU / 512 MB), scale when needed  
✅ Never put secrets in environment variables  
✅ Know the difference: execution role vs task role  
✅ Use immutable tags, never deploy :latest  

Next week: ALB, HTTPS, DNS - wiring to the internet.

---

## Homework

1. Draw the networking diagram for your ECS project
2. Calculate: what CIDR do you need? How many subnets?
3. Decide: NAT Gateway or public subnets for dev?
4. Write your task definition - what CPU/memory does your app need?
5. Look at the code in the repo
