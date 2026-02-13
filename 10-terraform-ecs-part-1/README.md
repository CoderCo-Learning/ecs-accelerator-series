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
