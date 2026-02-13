# ECS Project

ECS Project context.

## Objective

Build, containerise and deploy an application to AWS ECS with HTTPS and a custom domain using modern DevOps practices.

Final endpoint format:

```
app.yourdomain.com
```

## What You’re Building

A complete AWS deployment including:

- A containerised application exposing `/health`
- Amazon ECR image registry
- ECS (Fargate) service
- Application Load Balancer (ALB)
- Custom domain via Route 53
- TLS via AWS Certificate Manager (ACM)
- Infrastructure as Code using Terraform
- CI/CD automation using GitHub Actions (OIDC)


## Project Phases (High-Level)

### Application

- Lightweight app (Node, Go, Python, or BYO)
- Must expose:

```
GET /health → {"status":"ok"}
```

- Must run locally before Docker

### Containerisation

- Multi-stage Dockerfile
- Non-root runtime user
- Small image footprint
- `.dockerignore` included
- Prefer distroless or scratch if possible

### Image Registry

- Push Docker image to Amazon ECR
- Tag using version or commit SHA

### Manual Deployment (ClickOps First)

Deploy everything manually via AWS Console to understand how it works:

- ECR repository
- ECS cluster (Fargate recommended)
- Task definition
- Application Load Balancer
- Security groups
- Route 53 record (`app.<your-domain>`)
- ACM certificate for HTTPS

Once HTTPS works, destroy the infrastructure and move to Terraform.

### Infrastructure as Code (Terraform)

Rebuild the entire stack using Terraform.

Core components:

- VPC (public subnets)
- ECS cluster + Fargate service
- ECR repository
- ALB + listeners + target group
- ACM certificate
- Route53 DNS record
- IAM roles
- Security groups

-----
### CI/CD Automation

Automate the full workflow:

**Build & Push**

- Build Docker image
- Tag with commit SHA
- Push to ECR

**Terraform Deploy**

- `terraform init`
- `terraform plan`
- `terraform apply`

**Post-Deploy Health Check**
- Curl `https://app.<your-domain>/health`
- Fail pipeline if unhealthy

-----

Core principle:

> Understand manually > destroy > automate properly.
