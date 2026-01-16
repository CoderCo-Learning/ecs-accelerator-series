# Terraform Foundations – ECS Accelerator

This session introduces **Terraform fundamentals** before applying it to AWS and ECS.

The focus is on **correct mental models**, not syntax memorisation.

---

## Session Objectives

By the end of this session, you will understand:

- What Terraform is (and what it is not)
- How Terraform decides **resource order**
- What a **dependency graph** is
- Why **state** is critical
- The Terraform workflow

---

## Where Terraform Fits

You already know:

- **Docker** – what runs  
- **ECS** – where it runs  

Terraform answers:

> Who creates and manages the place it runs in?

Terraform is used to **build and maintain platforms**, not deploy applications.

---

## What Terraform Is

Terraform lets you **describe a desired end state**.

- You declare *what should exist*
- Terraform figures out *how to reach it*
- Execution order is derived automatically

> Terraform is a diff engine with memory.

---

## Dependency Graph (Key Concept)

Before creating anything, Terraform builds a **dependency graph**.

- Reads all `.tf` files
- Finds references between resources
- Determines correct creation order
- Executes in parallel where possible

**Order is derived, not written.**

### Example

If a container references an image:
- The image is created first
- The container is created after

References create dependencies.

If no dependency exists, Terraform runs resources in parallel.

---

## Providers

Terraform itself does nothing.

**Providers** teach Terraform how to talk to APIs.

Examples:
- AWS provider → AWS APIs
- Docker provider → Docker daemon
- Kubernetes provider → Kubernetes API

Terraform is **not AWS-specific**.

Version pinning is important to avoid unexpected breakage.

---

## Resources

A **resource** represents a real object managed by Terraform.

Examples:
- Docker container
- ECS cluster
- Load balancer
- IAM role

Key rules:
- One resource = one lifecycle
- Terraform owns what it creates
- Manual console changes cause drift

> If Terraform created it, the console is read-only.

---

## Terraform State

Terraform uses **state** to remember what it created.

- Maps Terraform resources to real objects
- Stores IDs and attributes
- Enables safe updates and deletes

State is:
- Required
- Not optional
- Critical to safe operation

> Terraform without state is just YAML with hope.

Local state is fine for learning.  
Remote state is required for teams (later sessions).

---

## Project Structure

A standard Terraform layout:

```bash
terraform/
├── main.tf
├── providers.tf
├── variables.tf
└── outputs.tf
```

## Terraform Workflow

Terraform always follows the same lifecycle:

```bash
terraform init
terraform plan
terraform apply
terraform destroy
```

init – prepares Terraform

plan – shows intended changes

apply – executes changes

destroy – removes resources safely
