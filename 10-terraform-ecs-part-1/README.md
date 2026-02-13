# Episode 10 – Terraform for ECS (Part 1)

## The Journey So Far

```
Episode 1-4:  You learned to containerise
Episode 5:    You pushed to ECR
Episode 6-8:  You learned Terraform foundations
Episode 9:    You deployed ECS manually (ClickOps)
```

**Now:** You destroy what you clicked and rebuild it as code.

---

## Why?

ClickOps taught you *what* AWS creates.

Terraform teaches you *how to automate it*.

- Reproducible
- Version controlled
- Reviewable
- Destroyable and rebuildable in minutes

---

## What We're Going Through Today

Everything you clicked in Episode 9:

| AWS Console | Terraform Resource |
|-------------|-------------------|
| VPC | `aws_vpc` |
| Subnets | `aws_subnet` |
| Internet Gateway | `aws_internet_gateway` |
| Route Table | `aws_route_table` |
| Security Group (ALB) | `aws_security_group` |
| Security Group (ECS) | `aws_security_group` |
| ECR Repository | `aws_ecr_repository` |
| ECS Cluster | `aws_ecs_cluster` |
| Task Definition | `aws_ecs_task_definition` |
| IAM Role (execution) | `aws_iam_role` |
| ALB | `aws_lb` |
| Target Group | `aws_lb_target_group` |
| Listener | `aws_lb_listener` |
| ECS Service | `aws_ecs_service` |
| ACM Certificate | `aws_acm_certificate` |
| Route53 Record | `aws_route53_record` |

That's a lot. We split it:

- **Part 1 (today):** Foundation - VPC, cluster, task definition
- **Part 2 (next week):** Wiring - ALB, HTTPS, DNS, service

---

## The Mental Model

```
┌─────────────────────────────────────────────────────────────┐
│                        PART 1 (Today)                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────────── VPC ───────────────────┐            │
│   │                                            │            │
│   │   ┌────────────┐    ┌────────────┐        │            │
│   │   │  Subnet A  │    │  Subnet B  │        │            │
│   │   │  (public)  │    │  (public)  │        │            │
│   │   └────────────┘    └────────────┘        │            │
│   │                                            │            │
│   │   ┌────────────────────────────────┐      │            │
│   │   │         ECS Cluster            │      │            │
│   │   │   ┌────────────────────────┐   │      │            │
│   │   │   │    Task Definition     │   │      │            │
│   │   │   │  (container spec)      │   │      │            │
│   │   │   └────────────────────────┘   │      │            │
│   │   └────────────────────────────────┘      │            │
│   │                                            │            │
│   └────────────────────────────────────────────┘            │
│                                                             │
│   ┌──────────────┐    ┌──────────────────────┐             │
│   │     ECR      │    │   IAM Execution Role │             │
│   │  (registry)  │    │   (pull images)      │             │
│   └──────────────┘    └──────────────────────┘             │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                      PART 2 (Next Week)                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Internet/Client/User → Route53 → ALB → Target Group → ECS Service → Tasks      │
│              ↓                                              │
│         ACM Cert + Route53                                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## The Dependency Chain

Terraform figures out order automatically, but you should understand it:

```
VPC
 └── Subnets
      └── Security Groups
           └── ECS Cluster
                └── Task Definition
                     └── ECS Service (needs ALB first - Part 2)
```

```
ECR Repository ──┐
                 ├── Task Definition (references image URI)
IAM Role ────────┘
```

If you try to create a task definition without:
- ECR repo → no image to pull
- IAM role → no permission to pull

Terraform handles this. But *you* need to understand why.

---

## Key Resources (Theory)

### 1. VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}
```

The network boundary. Everything lives inside this.

### 2. Subnets

```hcl
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  map_public_ip_on_launch = true  # Fargate needs this for public subnets
}
```

Why 2 subnets? ALB requires at least 2 AZs for high availability.

### 3. ECS Cluster

```hcl
resource "aws_ecs_cluster" "main" {
  name = "my-app-cluster"
}
```

That's it. A cluster is just a logical grouping. The magic is in the task definition.

### 4. Task Definition

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "my-app"
  network_mode             = "awsvpc"      # Required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}
```

This is the "recipe" - what container, how much CPU/memory, what ports.

### 5. IAM Execution Role

```hcl
resource "aws_iam_role" "ecs_execution" {
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

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
```

This lets ECS pull images from ECR and write logs to CloudWatch.

---

## For Next Session

- ECS Service (needs ALB)
- ALB (Part 2)
- ACM Certificate (Part 2)
- Route53 (Part 2)

Why? The service needs somewhere to send traffic. That's the ALB. We build the foundation first.

---

## Homework

Before Part 2:

1. Review your ClickOps deployment
2. Think about how each Console screen maps to a Terraform resource
3. Try writing `vpc.tf` yourself - just the VPC and subnets

---

## Key Takeaway

> Terraform is not magic. It's the same resources you clicked, written down.

If you understood ClickOps, you'll understand Terraform.

