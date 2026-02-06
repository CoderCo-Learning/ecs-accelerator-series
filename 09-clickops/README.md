# Episode 9 – ClickOps First: AWS Console Deep Dive

## Why this episode exists

Before automating infrastructure with Terraform or building CI/CD pipelines, it’s important to understand what AWS is actually creating for you.

The AWS Console is not the enemy.

Used correctly, it is a:

- learning tool
- debugging tool
- interview tool

Terraform comes **after** understanding – not before.

If you don’t understand what you’re automating, you’re just copy-pasting infrastructure.

---

## What is ClickOps (in this context)

ClickOps does **not** mean:
- running production manually forever
- clicking around without discipline
- avoiding Infrastructure as Code

ClickOps **does** mean:
- learning services through the AWS Console first
- understanding all available configuration options
- seeing how resources relate to each other
- building the correct mental model before automating

You can’t automate what you don’t understand.

---

## What you will build manually

In this session, everything is created using the AWS Console.

### Networking (VPC)

- A custom VPC
- Two public subnets across different Availability Zones
- Two private subnets across different Availability Zones
- An Internet Gateway attached to the VPC
- A NAT Gateway in a public subnet
- Public and private route tables with correct routing

### Compute (ECS)

- An ECS cluster using Fargate
- A task definition
  - CPU and memory configuration
  - Container definition
  - Port mappings
  - Logging configuration
  - IAM roles
- An ECS service running the task

### Load Balancing

- An Application Load Balancer (internet-facing)
- A target group using IP mode
- Listener configuration
- Security groups
- Connection between the ALB and the ECS service

---

## Learning goals

By the end of this episode, you should be able to:

- Explain how traffic flows from the internet to a container
- Understand the relationship between:
  - VPCs
  - subnets
  - route tables
  - gateways
  - load balancers
  - ECS services
- Recognise which AWS Console actions map to Terraform resources
- Read Terraform plans with confidence
- Use the AWS Console to debug Terraform deployments
- Confidently talk through AWS services in interviews

---

## Key concepts to pay attention to

While working through the console, make sure you notice:

- resource IDs and ARNs
- which IAM roles AWS creates automatically
- default values that are hidden in Terraform examples
- how security groups and networking actually interact
- how many steps are involved to do this manually

These details matter later when writing Infrastructure as Code.

---

## Homework

After completing the walkthrough:

1. Manually delete **all** created resources using the AWS Console
2. Pay attention to:
   - how long this takes
   - how easy it is to miss something
   - dependencies between resources
3. Reflect on why automation is valuable

Feeling the pain is part of the lesson.

---

## What’s next

In the next episode, we will:

- recreate this entire setup using Terraform
- reduce dozens of manual steps into a small number of files
- make all implicit behaviour explicit
- deploy the same architecture in minutes instead of hours

ClickOps first.
Automation second.
