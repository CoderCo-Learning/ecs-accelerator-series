# CI/CD Part 3 - Self-Hosted Runners, Secrets Management & Multi-Environment Deployments

## The Journey So Far

```
Episode 1-4:   You learned to containerise
Episode 5:     You pushed to ECR
Episode 6-8:   You learned Terraform foundations
Episode 9:     You deployed ECS manually (ClickOps)
Episode 10:    You rebuilt it all as Terraform
Episode 11:    You learned CI/CD concepts - what, why, how it works
Episode 12:    You built real pipelines - OIDC, build, deploy, PR scan, reusable workflows
```

Last session we built working pipelines and introduced reusable workflows. This session we cover three topics that take your CI/CD from "it works" to "it works in production at an organisation":

1. **Self-hosted runners** - running pipelines on your own infrastructure
2. **Secrets management** - how to handle credentials properly at every layer
3. **Multi-environment deployments** - dev to staging to prod with approval gates

---

## Part 1: Self-Hosted Runners

### Why Self-Hosted?

GitHub-hosted runners are great. Free, ephemeral, zero maintenance. But they have limits:

| Limitation | Impact |
|-----------|--------|
| **No VPC access** | Can't reach private RDS, internal APIs, private subnets |
| **2 vCPU / 7GB RAM** | Large Docker builds or Terraform plans are slow |
| **No persistent cache** | Every run re-downloads dependencies from scratch |
| **Shared infrastructure** | Compliance teams may not approve running sensitive workloads on GitHub's machines |
| **Cost at scale** | Free tier is 2,000 mins/month. A team of 20 doing 50 builds/day burns through that in days |

### When You Actually Need Them

**1. VPC Access**

Your pipeline needs to run `terraform plan` against an RDS in a private subnet. Or your integration tests hit an internal API. GitHub-hosted runners can't reach private networks.

```
GitHub-Hosted Runner                    Your AWS VPC
       |                                     |
       |  ---- BLOCKED ----------------->    |  Private RDS
       |  (no route to private subnet)       |  Internal APIs
       |                                     |  Private ECR
```

```
Self-Hosted Runner (in your VPC)        Your AWS VPC
       |                                     |
       |  ---- DIRECT ACCESS ----------->    |  Private RDS
       |  (same network)                     |  Internal APIs
       |                                     |  Private ECR
```

**2. Compliance / Data Sovereignty**

Regulated industries (finance, healthcare, government) may require that code and build artifacts never leave their network. GitHub-hosted runners are in GitHub's cloud. Self-hosted runners are on your infrastructure.

**3. Cost at Scale**

GitHub Actions pricing for hosted runners:
- Linux: $0.008/min
- macOS: $0.08/min

At 50 builds/day averaging 10 minutes each:
- Monthly: 50 x 10 x 30 = 15,000 minutes
- Cost: 15,000 x $0.008 = **$120/month** for Linux

Versus an EC2 `t3.medium` running 24/7:
- ~$30/month (on-demand), ~$12/month (reserved)
- Handles unlimited builds

The break-even is around 5,000-10,000 minutes/month depending on instance type.

**4. Build Performance**

Self-hosted runners can have:
- Persistent Docker layer cache (no re-pulling base images)
- Pre-installed tools (no setup time)
- More CPU/RAM (use `c5.2xlarge` for heavy builds)
- Local ECR endpoint (faster image push/pull within the same region)

A build that takes 8 minutes on a GitHub-hosted runner might take 2 minutes on a self-hosted runner with cached layers.

### Architecture

```
GitHub.com                          Your Infrastructure
   |                                      |
   |  1. Workflow triggered               |
   |     (push to main)                   |
   |                                      |
   |  2. "Any runner with label           |
   |      'self-hosted' available?"        |
   |---------------------------------->   |
   |                                      |  Runner Agent
   |  3. Runner polls GitHub,             |  (long-poll HTTPS)
   |     picks up the job                 |
   |<----------------------------------   |
   |                                      |
   |  4. Runner executes steps            |
   |     locally, streams logs            |
   |     back to GitHub                   |
   |<--------------------------------->  |
   |                                      |
   |  5. Job complete, status             |
   |     reported back                    |
   |<----------------------------------   |
```

**Important:** The runner connects **outbound** to GitHub. GitHub does not connect inbound to your runner. This means:
- No inbound firewall rules needed
- No public IP required (just outbound HTTPS)
- Works behind NAT, corporate firewalls, VPNs

### Setting Up a Self-Hosted Runner on EC2

#### Step 1: Create the EC2 Instance

Use an Amazon Linux 2023 or Ubuntu 22.04 instance. `t3.medium` is a good starting point.

Requirements:
- Outbound internet access (HTTPS to github.com)
- IAM instance profile if the runner needs AWS access (better than storing keys)
- Security group: outbound 443 only, no inbound rules needed
- At least 20GB EBS for Docker images

```hcl
# Terraform
resource "aws_instance" "github_runner" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id    # Private subnet is fine
  iam_instance_profile   = aws_iam_instance_profile.runner.name
  vpc_security_group_ids = [aws_security_group.runner.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = file("runner-setup.sh")

  tags = {
    Name = "github-actions-runner"
  }
}

resource "aws_security_group" "runner" {
  name   = "github-runner-sg"
  vpc_id = aws_vpc.main.id

  # No inbound rules - runner connects outbound to GitHub
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DNS resolution
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

#### Step 2: Install the Runner Agent

SSH into the instance:

```bash
# Create a directory for the runner
mkdir actions-runner && cd actions-runner

# Download the latest runner package
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz

# Install dependencies
sudo ./bin/installdependencies.sh
```

#### Step 3: Register the Runner with GitHub

Go to your repo (or org) settings:
- Repo: Settings > Actions > Runners > New self-hosted runner
- Org: Settings > Actions > Runners > New self-hosted runner

GitHub gives you a registration token:

```bash
./config.sh \
  --url https://github.com/CoderCo-Learning/ecs-accelerator-series \
  --token YOUR_REGISTRATION_TOKEN \
  --name "ec2-runner-1" \
  --labels "self-hosted,linux,x64,ecs-deploy" \
  --work "_work" \
  --runnergroup "Default"
```

The `--labels` flag is important. Labels are how your workflows target specific runners.

#### Step 4: Run as a Service

Don't run the runner in a terminal session. It dies when you disconnect.

```bash
# Install as a systemd service
sudo ./svc.sh install

# Start the service
sudo ./svc.sh start

# Check status
sudo ./svc.sh status

# The runner now starts on boot and restarts on failure
```

#### Step 5: Install Required Tools

The runner is bare. Install what your pipelines need:

```bash
# Docker
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Terraform
sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# jq (used in deploy scripts)
sudo apt-get install -y jq
```

### Using Self-Hosted Runners in Workflows

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, linux, ecs-deploy]  # Match by labels
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to ECS
        run: |
          # This runner is IN the VPC - it can reach private resources
          aws ecs update-service \
            --cluster production \
            --service my-api \
            --task-definition my-api:42
```

The `runs-on` array matches against runner labels. The job runs on any runner that has **all** the specified labels.

### Runner Labels

Labels let you route jobs to the right runners:

```yaml
# Build jobs go to runners with Docker and lots of CPU
build:
  runs-on: [self-hosted, linux, build, large]

# Deploy jobs go to runners in the production VPC
deploy:
  runs-on: [self-hosted, linux, deploy, prod-vpc]

# Terraform jobs go to runners with Terraform and AWS access
infra:
  runs-on: [self-hosted, linux, terraform]
```

You assign labels when registering the runner (`--labels`) or later in the GitHub UI under Settings > Actions > Runners.

### Runner Groups (Organisation Level)

Runner groups control which repos can use which runners:

```
Runner Group: "production-deployers"
  Runners: ec2-prod-1, ec2-prod-2
  Allowed repos: api-service, payments-service, auth-service

Runner Group: "dev-builders"
  Runners: ec2-dev-1, ec2-dev-2, ec2-dev-3
  Allowed repos: All repositories
```

This prevents a random experimental repo from deploying to production infrastructure.

### Security

Self-hosted runners come with security responsibilities that GitHub-hosted runners handle for you:

**1. Runners are persistent (not ephemeral by default)**

GitHub-hosted runners are destroyed after each job. Self-hosted runners keep running. Files from previous jobs may still be on disk. Docker images accumulate. Environment variables from previous runs could leak.

Clean up after each job:

```yaml
steps:
  # ... your actual steps ...

  - name: Cleanup
    if: always()
    run: |
      rm -rf $GITHUB_WORKSPACE/*
      docker system prune -af --volumes
```

Or better, use ephemeral runners (below).

**2. Never use self-hosted runners on public repos**

Anyone can open a PR against a public repo. If your workflow runs on PRs using a self-hosted runner, an attacker can submit a PR with a workflow that runs arbitrary code on your runner. That runner is in your VPC. Bad.

**Rule:** Self-hosted runners on **private repos only**. For public repos, use GitHub-hosted runners.

**3. Least privilege IAM**

If the runner has an IAM instance profile, scope it tightly. Don't give the runner admin access "because it's easier." That is a compromised runner away from a full account takeover.

### Ephemeral Runners

The gold standard for self-hosted runner security. An ephemeral runner handles exactly one job then de-registers itself:

```bash
./config.sh \
  --url https://github.com/CoderCo-Learning/ecs-accelerator-series \
  --token YOUR_TOKEN \
  --ephemeral
```

After the job completes, the runner process exits and removes itself from GitHub. For the next job, you spin up a new one.

This is how organisations run self-hosted runners at scale:

```
Job queued -> ASG launches EC2 -> Runner registers ->
Job runs -> Runner de-registers -> EC2 terminates
```

```
GitHub webhook                    Your Infrastructure
    |                                    |
    |  "workflow_job queued"              |
    |------------------------------>     |  Lambda / EventBridge
    |                                    |
    |                                    |  Launches EC2 from AMI
    |                                    |  (pre-baked with Docker, AWS CLI, etc.)
    |                                    |
    |                                    |  EC2 starts runner agent
    |  Runner picks up job               |  with --ephemeral flag
    |<------------------------------     |
    |                                    |
    |  Job runs, completes               |
    |------------------------------>     |
    |                                    |  Runner exits
    |                                    |  EC2 terminates
```

This gives you:
- VPC access and custom tooling (self-hosted benefits)
- Clean environment every run (GitHub-hosted benefits)
- Cost efficiency (only pay for compute during jobs)

Tools that automate this:
- **actions-runner-controller (ARC)** - Kubernetes-based auto-scaling for GitHub Actions runners
- **Philips terraform-aws-github-runner** - Terraform module for auto-scaling EC2 runners
- **GitHub's own larger runners** - GitHub-managed but with more resources and static IPs

---

## Part 2: Secrets Management

In Episode 12 we set up OIDC so the pipeline doesn't need stored AWS keys. But secrets management goes much deeper than pipeline credentials. Your application needs database passwords, API keys, encryption keys and service tokens. How you store, access and rotate them matters.

### The Layers of Secrets

There are three distinct layers where secrets live in a CI/CD setup:

```
Layer 1: Pipeline Secrets
  "How does my pipeline authenticate to AWS/Docker Hub/Slack?"
  -> GitHub Actions Secrets, OIDC, runner IAM roles

Layer 2: Infrastructure Secrets
  "How does Terraform get the RDS password to create the database?"
  -> Terraform variables, SSM Parameter Store, Secrets Manager

Layer 3: Application Secrets
  "How does my running container get the database connection string?"
  -> ECS task definition secrets, Secrets Manager, SSM Parameter Store
```

Each layer has different requirements for access control, rotation and audit.

### Layer 1: Pipeline Secrets

We covered this in Episode 12. Quick recap:

**Bad:** Long-lived AWS access keys stored in GitHub Secrets.

**Good:** OIDC. The pipeline assumes an IAM role and gets temporary credentials that expire in an hour.

**Best (with self-hosted runners):** IAM instance profile on the runner. No secrets stored anywhere. The runner's EC2 instance has an IAM role attached. AWS CLI and SDKs pick up credentials automatically from the instance metadata service. No OIDC needed. No secrets in GitHub at all.

```yaml
# GitHub-hosted runner (needs OIDC)
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: eu-west-1

# Self-hosted runner (IAM instance profile - no auth step needed)
steps:
  - name: Deploy
    run: aws ecs update-service ...   # Just works. Credentials from instance profile.
```

This is one of the underrated benefits of self-hosted runners. Your pipeline has zero secrets. The IAM role is attached to the EC2 instance. Nothing to leak, nothing to rotate, nothing stored in GitHub.

### Layer 2: Infrastructure Secrets (Terraform)

When Terraform creates a database, it needs to set a password. Where does that password come from?

**Bad: Hardcoded in Terraform**

```hcl
resource "aws_db_instance" "main" {
  master_password = "supersecret123"    # Don't do this
}
```

This ends up in your Terraform state file (in plaintext) and your git history (forever).

**Bad: terraform.tfvars**

```hcl
# terraform.tfvars
db_password = "supersecret123"
```

Better than hardcoding but still ends up in state. And someone will commit the tfvars file eventually.

**Good: Generate and store in Secrets Manager**

```hcl
resource "random_password" "db" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "my-app/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_db_instance" "main" {
  master_password = random_password.db.result
}
```

Terraform generates a random password, stores it in Secrets Manager and uses it for the RDS instance. The password is still in the Terraform state file (known limitation) but never in your code or git history.

**Terraform state file security:** Since state contains secrets in plaintext, your state backend must be encrypted. If you are using S3:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

The `encrypt = true` enables server-side encryption on the S3 object. Use a KMS key for additional control over who can decrypt the state.

### Layer 3: Application Secrets (Runtime)

This is the most important layer. Your running containers need secrets at runtime.

#### Option A: Environment Variables in Task Definition (Bad)

```json
"environment": [
  {
    "name": "DATABASE_URL",
    "value": "postgres://admin:supersecret123@my-db.cluster-xxx.eu-west-1.rds.amazonaws.com:5432/myapp"
  }
]
```

The password is in plaintext in the task definition. Anyone with ECS read access can see it. It shows up in the AWS console, in `aws ecs describe-task-definition` output, in CloudWatch logs if your app prints its config on startup.

#### Option B: AWS Secrets Manager (Recommended)

```json
"secrets": [
  {
    "name": "DATABASE_URL",
    "valueFrom": "arn:aws:secretsmanager:eu-west-1:123456789:secret:my-app/database-url"
  }
]
```

ECS pulls the secret from Secrets Manager at container startup. The value never appears in the task definition. The container sees it as a normal environment variable.

Requirements:
- The ECS task execution role needs `secretsmanager:GetSecretValue` permission
- The secret must exist before the task starts

Terraform setup:

```hcl
resource "aws_secretsmanager_secret" "db_url" {
  name = "my-app/database-url"
}

resource "aws_iam_role_policy" "ecs_secrets" {
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.db_url.arn]
      }
    ]
  })
}
```

In the task definition:

```hcl
resource "aws_ecs_task_definition" "app" {
  container_definitions = jsonencode([
    {
      name  = "api"
      image = "123456.dkr.ecr.eu-west-1.amazonaws.com/my-app:latest"
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.db_url.arn
        }
      ]
    }
  ])
}
```

#### Option C: SSM Parameter Store

Similar to Secrets Manager but cheaper and simpler for non-sensitive config:

```json
"secrets": [
  {
    "name": "API_ENDPOINT",
    "valueFrom": "arn:aws:ssm:eu-west-1:123456789:parameter/my-app/api-endpoint"
  }
]
```

SSM Parameter Store has two tiers:
- **Standard** - free, up to 10,000 parameters, 4KB max
- **Advanced** - $0.05/parameter/month, 8KB max, parameter policies (expiration, notification)

Use Parameter Store for config values (API endpoints, feature flags, non-secret settings). Use Secrets Manager for actual secrets (passwords, API keys, tokens).

#### Secrets Manager vs SSM Parameter Store

| | Secrets Manager | SSM Parameter Store |
|---|---|---|
| **Cost** | $0.40/secret/month + $0.05/10k API calls | Free (Standard) or $0.05/param/month (Advanced) |
| **Rotation** | Built-in automatic rotation with Lambda | Manual (you build rotation yourself) |
| **Max size** | 64KB | 4KB (Standard) / 8KB (Advanced) |
| **Cross-account** | Native support via resource policy | Requires IAM role assumption |
| **Best for** | Database creds, API keys, anything that needs rotation | Config values, feature flags, endpoints |

### Secret Rotation

Secrets that never change are secrets waiting to be compromised. Secrets Manager supports automatic rotation:

```hcl
resource "aws_secretsmanager_secret_rotation" "db" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.rotate_db_password.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

How rotation works for RDS:

1. Secrets Manager invokes a Lambda function
2. Lambda creates a new password in the database
3. Lambda updates the secret in Secrets Manager with the new password
4. Next time ECS starts a new task, it picks up the new password

For existing running tasks, you need to restart them to pick up the rotated secret. ECS does not hot-reload secrets. A rolling deploy (force new deployment) handles this.

AWS provides pre-built rotation Lambda functions for common services (RDS, Redshift, DocumentDB). For custom secrets you write your own Lambda.

### SOPS (Secrets OPerationS)

SOPS is a tool by Mozilla for encrypting secret files in git. Unlike the approaches above, SOPS lets you keep encrypted secrets alongside your code:

```yaml
# secrets.enc.yaml (encrypted - safe to commit)
database_url: ENC[AES256_GCM,data:abc123...,iv:xyz...]
api_key: ENC[AES256_GCM,data:def456...,iv:uvw...]
sops:
  kms:
    - arn: arn:aws:kms:eu-west-1:123456789:key/my-key-id
```

You encrypt with a KMS key. Only people/roles with access to that KMS key can decrypt.

```bash
# Encrypt a file
sops --encrypt --kms arn:aws:kms:eu-west-1:123456789:key/my-key secrets.yaml > secrets.enc.yaml

# Decrypt (requires KMS access)
sops --decrypt secrets.enc.yaml

# Edit in place (decrypts, opens editor, re-encrypts on save)
sops secrets.enc.yaml
```

SOPS is useful when:
- You want secrets versioned in git (encrypted)
- You want to diff secret changes in PRs (you can see which keys changed, not the values)
- You don't want to depend on Secrets Manager for everything

Your pipeline can decrypt SOPS files and inject them into the deployment process. The runner needs access to the KMS key (via IAM role or OIDC).

### The Full Picture

```
Pipeline Authentication
  Self-hosted runner: IAM instance profile (no secrets stored)
  GitHub-hosted runner: OIDC (temporary credentials)

Infrastructure Provisioning
  Terraform generates passwords with random_password
  Stores them in Secrets Manager
  State file encrypted in S3 with KMS

Application Runtime
  ECS task definition references Secrets Manager ARNs
  ECS pulls secrets at container startup
  Container sees normal environment variables
  Secrets Manager rotates passwords on a schedule

Non-secret Config
  SSM Parameter Store for endpoints, feature flags, region settings
  Referenced the same way in task definitions
```

No plaintext secrets in code. No long-lived keys in GitHub. Automatic rotation. Audit trail in CloudTrail.

---

## Part 3: Multi-Environment Deployments

### The Problem

So far we have been deploying to a single environment. Push to main, build, deploy. In reality you have multiple environments:

```
dev       ->    staging    ->    production
(wild west)    (pre-prod)       (here be users)
```

Each environment needs:
- Its own ECS cluster (or service)
- Its own set of secrets and config
- Its own deployment rules
- Different levels of approval

### GitHub Environments

GitHub Actions has a built-in concept of **environments**. They give you:
- **Protection rules** - require approvals before deploying
- **Wait timers** - enforce a delay before deployment starts
- **Environment secrets** - secrets scoped to a specific environment
- **Deployment branches** - restrict which branches can deploy to an environment

Set them up in your repo: Settings > Environments

```
Environment: "dev"
  No protection rules
  Secrets: AWS_ROLE_ARN (dev account role)

Environment: "staging"
  Required reviewers: none
  Wait timer: 0
  Secrets: AWS_ROLE_ARN (staging account role)

Environment: "production"
  Required reviewers: @team-leads
  Wait timer: 5 minutes
  Deployment branches: main only
  Secrets: AWS_ROLE_ARN (production account role)
```

### The Deployment Pipeline

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image: ${{ steps.build.outputs.uri }}
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - name: Build and push
        id: build
        run: |
          # ... build, scan, push to ECR ...
          echo "uri=$ECR_REGISTRY/my-app:${{ github.sha }}" >> $GITHUB_OUTPUT

  deploy-dev:
    needs: build
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: dev
      service: my-api
      container_name: api
      image: ${{ needs.build.outputs.image }}
    secrets: inherit

  deploy-staging:
    needs: deploy-dev
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: staging
      service: my-api
      container_name: api
      image: ${{ needs.build.outputs.image }}
    secrets: inherit

  deploy-production:
    needs: deploy-staging
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: production
      service: my-api
      container_name: api
      image: ${{ needs.build.outputs.image }}
    secrets: inherit
```

This deploys the **same image** through all environments. The image built from the commit SHA is what runs in dev, staging and production. No rebuilding per environment.

### Adding Approval Gates

The real power is in GitHub Environments with protection rules:

```yaml
  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production          # <-- This triggers the approval gate
    steps:
      - name: Deploy
        run: echo "Deploying to production..."
```

When the pipeline reaches `deploy-production`, GitHub pauses and sends a notification to the required reviewers. The job sits in "Waiting" state until someone approves (or it times out).

```
build -> deploy-dev -> deploy-staging -> [APPROVAL GATE] -> deploy-production
                                              |
                                              |  "Deploy #42 to production?"
                                              |  Requested by @engineer
                                              |  [Approve] [Reject]
```

This is configured entirely in the GitHub UI (Settings > Environments > production > Required reviewers). The workflow just references `environment: production` and GitHub handles the rest.

### Environment-Specific Configuration

Each environment has different config. The cleanest pattern is to use environment-level secrets and variables:

```yaml
  deploy-staging:
    needs: deploy-dev
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}    # staging-specific role
          aws-region: ${{ vars.AWS_REGION }}              # staging-specific region

      - name: Deploy
        run: |
          aws ecs update-service \
            --cluster ${{ vars.ECS_CLUSTER }} \
            --service ${{ vars.ECS_SERVICE }} \
            --task-definition ...
```

`secrets.AWS_ROLE_ARN` resolves to the staging account's role because the job has `environment: staging`. Same workflow code, different values per environment.

### Multi-Account Architecture

In production organisations, each environment is a separate AWS account:

```
AWS Organisation
  |
  |-- Dev Account (111111111111)
  |     ECS cluster: dev
  |     ECR: shared (or per-account)
  |
  |-- Staging Account (222222222222)
  |     ECS cluster: staging
  |     ECR: shared (or per-account)
  |
  |-- Production Account (333333333333)
  |     ECS cluster: production
  |     ECR: shared (or per-account)
  |
  |-- Shared Services Account (444444444444)
        ECR: central image registry
        GitHub Runner infrastructure
```

Each account has its own OIDC trust and IAM role. The pipeline assumes a different role per environment:

```yaml
  deploy-staging:
    environment: staging
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::222222222222:role/github-deploy
          aws-region: eu-west-1
```

Benefits:
- Blast radius is contained. A misconfigured dev deploy can't touch production.
- IAM policies are account-scoped. The dev role can't access production resources.
- Cost tracking per environment is automatic (per-account billing).
- Compliance teams can apply different controls per account.

### Promotion vs Rebuild

There are two approaches to multi-environment deployments. One is correct.

**Rebuild per environment (wrong):**
```
Push to main -> Build image -> Deploy to dev
                Build image -> Deploy to staging    (different image!)
                Build image -> Deploy to production  (different image!)
```

Each environment gets a different image built from the same code. But "same code" does not mean "same image." Build environments can vary. Dependencies can resolve differently. You are not testing what you deploy.

**Promote the same image (correct):**
```
Push to main -> Build image once -> Deploy to dev (image:abc123)
                                 -> Deploy to staging (image:abc123)
                                 -> Deploy to production (image:abc123)
```

One build. One image. Promoted through environments. The image you tested in staging is the exact image running in production. Byte for byte identical.

This is why we tag with the commit SHA. The image `my-app:abc123` is immutable. It is the same everywhere.

If images need to be in per-account ECR repositories, use ECR cross-account replication or ECR pull-through cache rather than rebuilding.

### Rollback in Multi-Environment

Rollback works the same as single-environment (Episode 12). Find the last known good commit SHA, trigger a deploy with that image. The pipeline promotes it through the environments.

For production emergencies, you might want a fast-path that skips dev and staging:

```yaml
on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: "Image tag (commit SHA) to deploy"
        required: true
      skip_lower_envs:
        description: "Skip dev and staging (emergency only)"
        type: boolean
        default: false

jobs:
  deploy-dev:
    if: ${{ !inputs.skip_lower_envs }}
    # ...

  deploy-staging:
    if: ${{ !inputs.skip_lower_envs }}
    needs: deploy-dev
    # ...

  deploy-production:
    needs: deploy-staging
    if: always() && (needs.deploy-staging.result == 'success' || inputs.skip_lower_envs)
    environment: production
    # ...
```

This gives you a manual trigger with an escape hatch for emergencies. The approval gate on production still applies.

---

## File Structure

```
13-cicd-3/
├── README.md                                    <- You are here
└── .github/
    └── workflows/
        ├── self-hosted-deploy.yml               <- Deploy using self-hosted runner
        └── multi-env-deploy.yml                 <- Multi-environment deployment pipeline
```

---

## Common Issues

**"Self-hosted runner offline"**
The runner agent crashed or the EC2 instance stopped. SSH in and check `sudo ./svc.sh status`. Common causes: disk full (Docker images), OOM kill, instance terminated by ASG.

**"Job queued but never starts"**
No runner matches the labels in `runs-on`. Labels are AND-matched. The runner needs all the labels the workflow requires.

**"Secrets not available in reusable workflow"**
Pass secrets explicitly with `secrets:` or use `secrets: inherit`. The reusable workflow must declare expected secrets in `on.workflow_call.secrets`.

**"Secret not found in ECS task"**
The ECS task execution role needs `secretsmanager:GetSecretValue` permission for the specific secret ARN. Check the role policy. Make sure the secret ARN matches exactly.

**"Deployment waiting for approval but nobody got notified"**
Check that required reviewers are set in Settings > Environments > production. Reviewers must have write access to the repo.

**"Same image tag in dev and prod but different behaviour"**
Check environment variables and secrets. The image is the same but config differs per environment. Verify that environment-scoped secrets and variables are set correctly.

---

## Key Takeaways

1. **Self-hosted runners** solve VPC access, compliance, cost and performance. Use ephemeral mode for security.
2. **Never use self-hosted runners on public repos.** Anyone can run code on your infrastructure via a PR.
3. **Secrets have three layers** - pipeline auth (OIDC/instance profiles), infrastructure (Secrets Manager), application runtime (ECS secrets from Secrets Manager/SSM).
4. **Never put secrets in plaintext** - not in code, not in task definitions, not in Terraform variables. Use Secrets Manager or SSM Parameter Store.
5. **Promote images, don't rebuild** - one build, one image, promoted through dev > staging > prod. The SHA tag is your source of truth.
6. **GitHub Environments** give you approval gates, scoped secrets and deployment branch restrictions with zero custom code.

---

## What's Coming Next

- Infrastructure pipelines (Terraform plan/apply in CI/CD)
- Advanced deployment strategies (blue/green, canary)
- GitOps patterns
- Local pipeline testing with `act`

---

## Resources

- [Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
- [actions-runner-controller (ARC)](https://github.com/actions/actions-runner-controller)
- [GitHub Environments](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [SOPS](https://github.com/getsops/sops)
- [Philips Terraform AWS GitHub Runner](https://github.com/philips-labs/terraform-aws-github-runner)
