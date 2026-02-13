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
│  │                  10.0.0.0/16                       │  │
│  │   Your resources live here, isolated from others  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### CIDR Block

The IP range for your VPC.

| CIDR | IP Addresses |
|------|--------------|
| /16 | 65,536 |
| /24 | 256 |
| /28 | 16 |

**Best practice:** Use `10.0.0.0/16` for most projects. Room to grow.

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true   # Instances get DNS names
  enable_dns_support   = true   # Required for ECS service discovery
}
```

---

## Subnets

Subdivisions of your VPC. Carve up your VPC into smaller networks.

```
┌─────────────────────────────────────────────────────────┐
│                    VPC: 10.0.0.0/16                      │
│                                                          │
│   ┌─────────────────┐    ┌─────────────────┐            │
│   │  Public Subnet  │    │  Public Subnet  │            │
│   │  10.0.1.0/24    │    │  10.0.2.0/24    │            │
│   │     AZ-a        │    │     AZ-b        │            │
│   │  ALB, NAT GW    │    │  ALB            │            │
│   └─────────────────┘    └─────────────────┘            │
│                                                          │
│   ┌─────────────────┐    ┌─────────────────┐            │
│   │ Private Subnet  │    │ Private Subnet  │            │
│   │  10.0.10.0/24   │    │  10.0.11.0/24   │            │
│   │     AZ-a        │    │     AZ-b        │            │
│   │  ECS Tasks, RDS │    │  ECS Tasks, RDS │            │
│   └─────────────────┘    └─────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

### Public vs Private

**Public Subnet:**
- Has route to Internet Gateway
- Resources can have public IPs
- Use for: ALB, NAT Gateway, bastion hosts

**Private Subnet:**
- No direct internet route
- Resources hidden from public
- Use for: ECS tasks, databases
- Reaches internet via NAT Gateway

### Why Multiple AZs?

High availability. If AZ-a goes down, AZ-b keeps running.

**ALB requires subnets in at least 2 AZs.**

```hcl
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  map_public_ip_on_launch = true  # Required for Fargate in public subnets
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}
```

---

## Internet Gateway (IGW)

The door between your VPC and the public internet. Without IGW, nothing can reach the internet.

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

**One IGW per VPC.** That's all you need.

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
```

---

## NAT Gateway

Allows private subnets to reach the internet (outbound only).

ECS tasks in private subnets need to:
- Pull Docker images from ECR
- Download packages
- Call external APIs

But you don't want them exposed to the internet.

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

### NAT Gateway vs NAT Instance

| | NAT Gateway | NAT Instance |
|--|-------------|--------------|
| Managed | Yes (AWS) | No (you) |
| High Availability | Built-in | You configure |
| Bandwidth | Up to 45 Gbps | Instance dependent |
| Cost | ~$0.045/hr + data | Instance cost |

**Best practice:** Use NAT Gateway. Managed, scales automatically.

### Cost Warning

NAT Gateway costs ~$32/month + data transfer.

For dev/staging:
- Use public subnets with Fargate (cheaper, less secure)
- Use VPC endpoints for ECR/S3/CloudWatch (no NAT needed for AWS services)

```hcl
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id  # Must be in public subnet
  
  depends_on = [aws_internet_gateway.main]
}
```

---

## Route Tables

Traffic rules. Tells AWS where to send network traffic. Every subnet needs a route table.

### Public Route Table

Routes `0.0.0.0/0` (everything) to the Internet Gateway.

```
Destination     │ Target
────────────────┼──────────────────
10.0.0.0/16     │ local (within VPC)
0.0.0.0/0       │ igw-xxx (Internet Gateway)
```

### Private Route Table

Routes `0.0.0.0/0` to the NAT Gateway.

```
Destination     │ Target
────────────────┼──────────────────
10.0.0.0/16     │ local (within VPC)
0.0.0.0/0       │ nat-xxx (NAT Gateway)
```

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

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

---

## Security Groups

Virtual firewall for resources. Controls inbound and outbound traffic.

### Best Practices

1. **Least privilege** - only open ports you need
2. **Reference security groups, not IPs** - use `source_security_group_id`
3. **Separate SGs per tier** - ALB SG, ECS SG, RDS SG

```hcl
# ALB Security Group - accepts traffic from internet
resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
}

# ECS Security Group - only accepts traffic from ALB
resource "aws_security_group" "ecs" {
  name   = "ecs-tasks-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # Only from ALB!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

ECS tasks only accept traffic from ALB - not directly from internet.

---

## ECS Components

### ECS Cluster

Logical grouping of tasks and services. Just a namespace.

```hcl
resource "aws_ecs_cluster" "main" {
  name = "my-app-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
```

### Task Definition

The recipe. What container, how much CPU/memory, ports, logging.

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "my-app"
  network_mode             = "awsvpc"      # Required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]
  }])
}
```

### IAM Execution Role

Lets ECS pull images from ECR and write logs to CloudWatch. Without this, tasks can't start.

---

## Key Takeaway

Now you understand why each component exists:
- **VPC** - isolation
- **Subnets** - organisation + AZ redundancy  
- **IGW** - internet access
- **NAT Gateway** - outbound for private resources
- **Route Tables** - traffic direction
- **Security Groups** - firewall

Next week: ALB, HTTPS, DNS.

---

## Homework

1. Draw the networking diagram for your ECS project
2. Decide: public subnets only (cheaper) or public + private (more secure)?
3. Look at the code in the repo

---

## ECS Deep Dive

### What is ECS?

Elastic Container Service. AWS managed container orchestration. You tell AWS what containers to run, ECS handles scheduling, scaling, health checks, networking.

Think of ECS as a hotel manager. You describe the room requirements (task definition), the manager assigns rooms (scheduling) and handles housekeeping (health checks, restarts).

### Fargate vs EC2 Launch Type

**Fargate (Serverless):**
- AWS manages the servers
- No EC2 instances to manage
- Pay per task (CPU + memory + time)
- Best for: most workloads, variable traffic, simplicity

**EC2 Launch Type:**
- You manage EC2 instances
- ECS agent runs on each instance
- More control, more complexity
- Best for: GPU workloads, specific instance types, cost optimisation at scale

For the ECS project, use Fargate. Simpler, no servers to manage.

---

## ECS Cluster

Logical grouping of tasks and services. A namespace - a boundary for your application.

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

A cluster can have multiple services. Each service runs multiple tasks.

```hcl
resource "aws_ecs_cluster" "main" {
  name = "my-app-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"  # CloudWatch metrics for containers
  }
}
```

---

## Task Definition

The blueprint. Describes HOW to run your container.

```
┌─────────────────────────────────────────────────┐
│              Task Definition                     │
│              "my-app:3"                          │
│                                                  │
│  Family: my-app                                  │
│  Revision: 3                                     │
│                                                  │
│  Container Definition:                           │
│    Name: app                                     │
│    Image: 123456.dkr.ecr.../:latest             │
│    Port: 80                                      │
│    CPU: 256                                      │
│    Memory: 512                                   │
│                                                  │
│  Network Mode: awsvpc                           │
│  Execution Role: ecs-execution-role             │
└─────────────────────────────────────────────────┘
```

### Key Settings

**Family and Revision:**
- Family = name of the task definition
- Revision = version number (auto-increments)
- Together: my-app:3 (family:revision)

**Network Mode:**
- `awsvpc` - each task gets its own ENI. Required for Fargate.
- `bridge` - Docker bridge network. EC2 only.
- `host` - Uses host network. EC2 only.

For Fargate, always use `awsvpc`.

**CPU and Memory (Fargate):**

| CPU | Memory Options |
|-----|----------------|
| 256 | 512, 1024, 2048 |
| 512 | 1024 - 4096 |
| 1024 | 2048 - 8192 |
| 2048 | 4096 - 16384 |
| 4096 | 8192 - 30720 |

Start small. 256 CPU / 512 memory is enough for most simple apps.

---

## Container Definition

Inside the task definition. Describes the actual container.

```hcl
container_definitions = jsonencode([{
  name      = "app"
  image     = "123456.dkr.ecr.../my-app:v1.2.3"
  essential = true
  
  portMappings = [{
    containerPort = 80
    protocol      = "tcp"
  }]
  
  environment = [
    { name = "NODE_ENV", value = "production" }
  ]
  
  secrets = [
    { name = "DB_PASSWORD", valueFrom = "arn:aws:ssm:..." }
  ]
  
  logConfiguration = {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = "/ecs/my-app"
      "awslogs-region"        = "eu-west-2"
      "awslogs-stream-prefix" = "ecs"
    }
  }
}])
```

### Essential Container

`essential = true` means if this container stops, the whole task stops.

### Environment vs Secrets

- `environment` - plain text, visible in console
- `secrets` - pulled from SSM Parameter Store or Secrets Manager at runtime

**Never put passwords in environment. Always use secrets.**

### Logging

`awslogs` driver sends stdout/stderr to CloudWatch Logs. Essential for debugging.

```hcl
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/my-app"
  retention_in_days = 30
}
```

---

## IAM Roles - Execution vs Task

Two different roles. People confuse these constantly.

```
┌─────────────────────────────────────────────────────────┐
│                                                          │
│   EXECUTION ROLE                    TASK ROLE            │
│   (ECS Agent uses this)             (Your app uses this) │
│                                                          │
│   - Pull images from ECR            - Call S3            │
│   - Write logs to CloudWatch        - Call DynamoDB      │
│   - Pull secrets from SSM           - Call SQS           │
│                                                          │
│   Required for task to START        Optional             │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Execution Role

Used by ECS agent to set up the task. Without this, task can't start.

```hcl
resource "aws_iam_role" "ecs_execution" {
  name = "ecs-execution-role"

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
```

### Task Role

Used by your application code. Only needed if your app calls AWS APIs.

For simple apps that only respond to HTTP, you don't need a task role.

---

## ECR - Elastic Container Registry

AWS managed Docker registry. Where your images live.

### Image URI Format

```
123456789012.dkr.ecr.eu-west-2.amazonaws.com/my-app:v1.2.3
└──────────────────────────────────────────────┘ └────┘ └────┘
              Repository URL                    Name   Tag
```

### Tagging Strategy

**Never use :latest in production.** Use immutable tags:
- Semantic version: `v1.2.3`
- Git commit SHA: `abc123f`
- Build number: `build-456`

Why? `:latest` can change. You won't know what version is running. Can't rollback reliably.

### Lifecycle Policy

Clean up old images automatically.

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "my-app"
  image_tag_mutability = "IMMUTABLE"  # Prevent tag overwrites

  image_scanning_configuration {
    scan_on_push = true  # Scan for vulnerabilities
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```
