# CI/CD Part 3 - Reusable Workflows, Composite Actions & Self-Hosted Runners

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

Last session we built working pipelines. This session we go deeper into two things that separate a hobby project pipeline from an engineering organisation's CI/CD:

1. **Reusable workflows & composite actions** - how to stop copy-pasting YAML across repos
2. **Self-hosted runners** - how to run pipelines on your own infrastructure

---

## Why This Matters

Imagine you have 15 microservices. Each one needs a CI pipeline that builds a Docker image, scans it and pushes to ECR. Each one needs a CD pipeline that deploys to ECS.

Without reusability, you have 30+ workflow files across 15 repos. All slightly different. Someone fixes a bug in one, forgets to update the others. Six months later you've got 15 variations of the same pipeline and nobody knows which one is correct.

This is the same problem Terraform modules solve for infrastructure. You wouldn't copy-paste 500 lines of Terraform into every project. You'd write a module and call it with different inputs. CI/CD pipelines deserve the same treatment.

---

## Part 1: Reusable Workflows - Deep Dive

We introduced reusable workflows in Episode 12. Now let's go deeper.

### What Is a Reusable Workflow?

A reusable workflow is a complete workflow file that other workflows can call. It runs as a **separate job** in the caller's pipeline. Think of it as a function that takes inputs and runs an entire job.

The key trigger is `workflow_call`:

```yaml
# .github/workflows/reusable-docker-build.yml
name: Reusable Docker Build

on:
  workflow_call:
    inputs:
      image_name:
        required: true
        type: string
      dockerfile:
        required: false
        type: string
        default: "Dockerfile"
      context:
        required: false
        type: string
        default: "."
    secrets:
      AWS_ROLE_ARN:
        required: true
    outputs:
      image_uri:
        description: "Full image URI with tag"
        value: ${{ jobs.build.outputs.image }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image: ${{ steps.meta.outputs.uri }}
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-west-1

      - name: Login to ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and tag
        run: |
          IMAGE="${{ steps.ecr.outputs.registry }}/${{ inputs.image_name }}:${{ github.sha }}"
          docker build -t "$IMAGE" -f ${{ inputs.dockerfile }} ${{ inputs.context }}
          echo "uri=$IMAGE" >> $GITHUB_OUTPUT
        id: meta

      - name: Scan with Grype
        uses: anchore/scan-action@v3
        with:
          image: ${{ steps.meta.outputs.uri }}
          fail-build: true
          severity-cutoff: high

      - name: Push to ECR
        run: docker push ${{ steps.meta.outputs.uri }}
```

### Calling a Reusable Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]

jobs:
  build:
    uses: ./.github/workflows/reusable-docker-build.yml
    with:
      image_name: my-api
    secrets:
      AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}

  deploy:
    needs: build
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: production
      service: my-api
      container_name: api
      image: ${{ needs.build.outputs.image_uri }}
```

Notice the caller job has `uses:` instead of `runs-on:` + `steps:`. The entire job is delegated to the reusable workflow.

### Cross-Repo Reusable Workflows

This is where it gets powerful for organisations. You create a central repo with your standard workflows:

```
CoderCo/shared-workflows/
  .github/workflows/
    reusable-docker-build.yml
    reusable-ecs-deploy.yml
    reusable-terraform-plan.yml
    reusable-terraform-apply.yml
```

Any repo in the org can call them:

```yaml
jobs:
  build:
    uses: CoderCo/shared-workflows/.github/workflows/reusable-docker-build.yml@main
    with:
      image_name: payments-api
    secrets:
      AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}
```

The `@main` at the end is the ref (branch, tag or SHA). For production, pin to a tag:

```yaml
uses: CoderCo/shared-workflows/.github/workflows/reusable-docker-build.yml@v2.1.0
```

**One place to update, every repo gets the fix.** When you find a vulnerability in your build process or need to add a new scanning step, you update one file in the shared repo. Every team benefits immediately (or on their next pin update if they're using tags).

### Reusable Workflow Constraints

There are rules you need to know:

| Constraint | Detail |
|-----------|--------|
| **Max nesting depth** | 4 levels. A workflow can call a reusable workflow, which can call another, up to 4 deep. Don't go that deep. |
| **Max reusable workflows per file** | 20 per workflow file |
| **env context** | Not passed down. The caller's `env:` block is not available in the reusable workflow. Pass values as inputs instead. |
| **Secrets** | Must be explicitly passed. The reusable workflow doesn't inherit the caller's secrets unless you use `secrets: inherit`. |
| **Concurrency** | Each reusable workflow call is a separate job. Concurrency groups apply at the caller level. |

### `secrets: inherit`

Instead of passing each secret individually:

```yaml
jobs:
  build:
    uses: ./.github/workflows/reusable-build.yml
    secrets:
      AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}
      SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
      DATADOG_API_KEY: ${{ secrets.DATADOG_API_KEY }}
```

You can pass all secrets at once:

```yaml
jobs:
  build:
    uses: ./.github/workflows/reusable-build.yml
    secrets: inherit
```

This is convenient but less explicit. For shared workflows across repos, explicitly declaring secrets is better because it documents what the workflow needs.

---

## Part 2: Composite Actions - Reusable Steps

### Reusable Workflows vs Composite Actions

This is where people get confused. Both provide reusability. The difference is **what** they encapsulate:

| | Reusable Workflow | Composite Action |
|---|---|---|
| **Scope** | Entire job (with its own runner) | Steps within a job |
| **Trigger** | `workflow_call` | Used in a step with `uses:` |
| **Runner** | Gets its own runner (or inherits via `runs-on`) | Runs on the calling job's runner |
| **When to use** | Complete pipelines (build, deploy, infra) | Repeated sequences of steps (setup, scan, notify) |
| **Analogy** | Terraform module | Terraform `local` block or a shell function |

**Rule of thumb:** If you need a whole job with its own environment, use a reusable workflow. If you need a few steps you keep repeating inside jobs, use a composite action.

### What Is a Composite Action?

A composite action bundles multiple steps into a single reusable step. It's defined in an `action.yml` file.

```
my-org/docker-build-scan/
  action.yml
```

```yaml
# action.yml
name: "Docker Build & Scan"
description: "Builds a Docker image and scans it with Grype"

inputs:
  image_name:
    description: "Name for the Docker image"
    required: true
  dockerfile:
    description: "Path to Dockerfile"
    required: false
    default: "Dockerfile"
  severity_cutoff:
    description: "Minimum severity to fail on"
    required: false
    default: "high"

outputs:
  image_tag:
    description: "The full image tag that was built"
    value: ${{ steps.build.outputs.tag }}

runs:
  using: "composite"
  steps:
    - name: Build image
      id: build
      shell: bash
      run: |
        TAG="${{ inputs.image_name }}:${{ github.sha }}"
        docker build -t "$TAG" -f ${{ inputs.dockerfile }} .
        echo "tag=$TAG" >> $GITHUB_OUTPUT

    - name: Scan with Grype
      uses: anchore/scan-action@v3
      with:
        image: ${{ steps.build.outputs.tag }}
        fail-build: true
        severity-cutoff: ${{ inputs.severity_cutoff }}
```

**Key differences from a reusable workflow:**
- Uses `runs: using: "composite"` instead of `on: workflow_call`
- Each step needs `shell: bash` (or another shell) for `run:` commands
- It doesn't define jobs - it defines steps that merge into the caller's job

### Using a Composite Action

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build and scan
        uses: CoderCo/docker-build-scan@v1   # <-- composite action
        with:
          image_name: my-app
          severity_cutoff: critical

      - name: Push to registry
        run: docker push my-app:${{ github.sha }}
```

Notice it's used as a **step** inside a job, not as a job itself. It runs on the same runner as the calling job. It shares the same filesystem, environment and context.

### Local Composite Actions

You can also define composite actions inside the same repo:

```
my-repo/
  .github/
    actions/
      docker-build-scan/
        action.yml
    workflows/
      ci.yml
```

Reference it with a relative path:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: ./.github/actions/docker-build-scan
    with:
      image_name: my-app
```

This is great for repo-specific reusable steps that don't need to be shared across the org.

### Real-World Composite Action Examples

**Setup & Auth composite action:**

```yaml
# .github/actions/aws-ecr-setup/action.yml
name: "AWS ECR Setup"
description: "OIDC auth to AWS and login to ECR"

inputs:
  role_arn:
    required: true
  aws_region:
    required: false
    default: "eu-west-1"

outputs:
  registry:
    description: "ECR registry URI"
    value: ${{ steps.ecr.outputs.registry }}

runs:
  using: "composite"
  steps:
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ inputs.role_arn }}
        aws-region: ${{ inputs.aws_region }}

    - name: Login to ECR
      id: ecr
      uses: aws-actions/amazon-ecr-login@v2
```

Now every workflow that needs AWS+ECR does one step instead of two:

```yaml
- uses: ./.github/actions/aws-ecr-setup
  with:
    role_arn: ${{ secrets.AWS_ROLE_ARN }}
```

**Slack notification composite action:**

```yaml
# .github/actions/slack-notify/action.yml
name: "Slack Deploy Notification"
description: "Send deployment status to Slack"

inputs:
  status:
    required: true
  service:
    required: true
  webhook_url:
    required: true

runs:
  using: "composite"
  steps:
    - name: Send notification
      shell: bash
      run: |
        if [ "${{ inputs.status }}" = "success" ]; then
          EMOJI=":white_check_mark:"
          COLOR="good"
        else
          EMOJI=":x:"
          COLOR="danger"
        fi

        curl -X POST ${{ inputs.webhook_url }} \
          -H 'Content-type: application/json' \
          -d "{
            \"attachments\": [{
              \"color\": \"$COLOR\",
              \"text\": \"$EMOJI *${{ inputs.service }}* deploy: ${{ inputs.status }}\nCommit: \`${{ github.sha }}\`\nActor: ${{ github.actor }}\"
            }]
          }"
```

### When to Use What

```
"I need to standardise our entire build pipeline across 10 repos"
  → Reusable workflow

"I keep writing the same 3 setup steps in every job"
  → Composite action

"I need a deploy pipeline that other workflows trigger after build"
  → Reusable workflow

"I want a single step that handles Docker build + scan + tag"
  → Composite action

"I need to run a job on a specific runner with specific permissions"
  → Reusable workflow

"I need to abstract away a curl + jq sequence into a clean interface"
  → Composite action
```

---

## Part 3: Self-Hosted Runners

### Why Self-Hosted?

GitHub-hosted runners are great. Free, ephemeral, zero maintenance. But they have limits:

| Limitation | Impact |
|-----------|--------|
| **No VPC access** | Can't reach private RDS, internal APIs, private subnets |
| **2 vCPU / 7GB RAM** | Large Docker builds or Terraform plans are slow |
| **No persistent cache** | Every run re-downloads dependencies from scratch |
| **Shared infrastructure** | Compliance teams may not approve running sensitive workloads on GitHub's machines |
| **Cost at scale** | Free tier is 2,000 mins/month. A team of 20 doing 50 builds/day burns through that in days |

### When You Actually Need Self-Hosted Runners

**1. VPC Access**

Your pipeline needs to run `terraform plan` against an RDS instance in a private subnet. Or your integration tests hit an internal API. GitHub-hosted runners can't reach private networks.

```
GitHub-Hosted Runner                    Your AWS VPC
       │                                     │
       │  ──── BLOCKED ────────────────►     │  Private RDS
       │  (no route to private subnet)       │  Internal APIs
       │                                     │  Private ECR
```

```
Self-Hosted Runner (in your VPC)        Your AWS VPC
       │                                     │
       │  ──── DIRECT ACCESS ──────────►     │  Private RDS
       │  (same network)                     │  Internal APIs
       │                                     │  Private ECR
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
   │                                      │
   │  1. Workflow triggered               │
   │     (push to main)                   │
   │                                      │
   │  2. "Any runner with label           │
   │      'self-hosted' available?"        │
   │──────────────────────────────────►   │
   │                                      │  Runner Agent
   │  3. Runner polls GitHub,             │  (long-poll HTTPS)
   │     picks up the job                 │
   │◄──────────────────────────────────   │
   │                                      │
   │  4. Runner executes steps            │
   │     locally, streams logs            │
   │     back to GitHub                   │
   │◄────────────────────────────────►   │
   │                                      │
   │  5. Job complete, status             │
   │     reported back                    │
   │◄──────────────────────────────────   │
```

**Important:** The runner connects **outbound** to GitHub. GitHub doesn't connect inbound to your runner. This means:
- No inbound firewall rules needed
- No public IP required (just outbound HTTPS)
- Works behind NAT, corporate firewalls, VPNs

### Setting Up a Self-Hosted Runner on EC2

#### Step 1: Create the EC2 Instance

Use an Amazon Linux 2023 or Ubuntu 22.04 instance. `t3.medium` is a good starting point for most workloads.

Requirements:
- Outbound internet access (HTTPS to github.com)
- IAM instance profile if the runner needs AWS access (better than storing keys)
- Security group: outbound 443 only, no inbound rules needed
- At least 20GB EBS for Docker images

```bash
# If using Terraform (which you should be by now)
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

SSH into the instance and run:

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

GitHub gives you a registration token. Run:

```bash
# Configure the runner
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

Don't run the runner in a terminal session. It'll die when you disconnect.

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

### Runner Labels - Organising Your Fleet

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

For organisations, runner groups control which repos can use which runners:

```
Runner Group: "production-deployers"
  Runners: ec2-prod-1, ec2-prod-2
  Allowed repos: api-service, payments-service, auth-service

Runner Group: "dev-builders"
  Runners: ec2-dev-1, ec2-dev-2, ec2-dev-3
  Allowed repos: All repositories
```

This prevents a random experimental repo from deploying to production infrastructure.

### Security Considerations

Self-hosted runners come with security responsibilities that GitHub-hosted runners handle for you:

**1. Runners are persistent (not ephemeral by default)**

GitHub-hosted runners are destroyed after each job. Self-hosted runners keep running. This means:
- Files from previous jobs may still be on disk
- Docker images and layers accumulate
- Environment variables from previous runs could leak

**Mitigation:** Clean up after each job:

```yaml
steps:
  # ... your actual steps ...

  - name: Cleanup
    if: always()
    run: |
      # Remove workspace files
      rm -rf $GITHUB_WORKSPACE/*
      # Prune Docker
      docker system prune -af --volumes
```

Or better, use **ephemeral runners** (covered below).

**2. Don't use self-hosted runners on public repos**

Anyone can open a PR against a public repo. If your workflow runs on PRs and uses a self-hosted runner, an attacker can submit a PR with a workflow that runs arbitrary code on your runner. That runner is in your VPC. Bad.

**Rule:** Self-hosted runners on **private repos only**. For public repos, use GitHub-hosted runners.

**3. Least privilege IAM**

If the runner has an IAM instance profile, scope it tightly:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition"
      ],
      "Resource": "*"
    }
  ]
}
```

Don't give the runner admin access "because it's easier." That's a compromised runner away from a full account takeover.

### Ephemeral Runners (JIT)

The gold standard for self-hosted runner security. An ephemeral runner handles exactly one job and then de-registers itself:

```bash
./config.sh \
  --url https://github.com/CoderCo-Learning/ecs-accelerator-series \
  --token YOUR_TOKEN \
  --ephemeral
```

After the job completes, the runner process exits and removes itself from GitHub. For the next job, you need to spin up a new runner.

This is how organisations run self-hosted runners at scale:

```
Job queued → Auto-scaling group launches EC2 → Runner registers →
Job runs → Runner de-registers → EC2 terminates
```

Tools that automate this:
- **actions-runner-controller (ARC)** - Kubernetes-based auto-scaling for GitHub Actions runners
- **Philips terraform-aws-github-runner** - Terraform module for auto-scaling EC2 runners
- **GitHub's own larger runners** - GitHub-managed but with more resources and static IPs

### Ephemeral Runners with Auto-Scaling (Conceptual)

```
GitHub webhook                    Your Infrastructure
    │                                    │
    │  "workflow_job queued"              │
    │──────────────────────────────►     │  Lambda / EventBridge
    │                                    │
    │                                    │  Launches EC2 from AMI
    │                                    │  (pre-baked with Docker, AWS CLI, etc.)
    │                                    │
    │                                    │  EC2 starts runner agent
    │  Runner picks up job               │  with --ephemeral flag
    │◄──────────────────────────────     │
    │                                    │
    │  Job runs, completes               │
    │──────────────────────────────►     │
    │                                    │  Runner exits
    │                                    │  EC2 terminates
    │                                    │
```

This gives you the best of both worlds:
- VPC access and custom tooling (self-hosted benefits)
- Clean environment every run (GitHub-hosted benefits)
- Cost efficiency (only pay for compute during jobs)

---

## Part 4: Putting It Together - An Organisation's CI/CD

Here's how a real organisation might structure their CI/CD using everything we've covered across Episodes 11-13:

```
CoderCo/
├── shared-workflows/                    ← Central repo
│   └── .github/workflows/
│       ├── reusable-docker-build.yml    ← Build, scan, push
│       ├── reusable-ecs-deploy.yml      ← ECS task def + deploy
│       └── reusable-terraform.yml       ← Plan + apply
│
├── shared-actions/                      ← Central repo
│   ├── aws-ecr-setup/
│   │   └── action.yml                   ← Composite: OIDC + ECR login
│   ├── slack-notify/
│   │   └── action.yml                   ← Composite: Slack notifications
│   └── docker-build-scan/
│       └── action.yml                   ← Composite: Build + Grype scan
│
├── infra/                               ← Terraform repo
│   ├── modules/
│   │   └── github-runner/               ← Runner infrastructure module
│   ├── environments/
│   │   ├── dev/
│   │   └── prod/
│   └── .github/workflows/
│       └── terraform.yml                ← Calls shared reusable-terraform
│
├── api-service/                         ← Application repo
│   └── .github/workflows/
│       ├── ci.yml                       ← Calls shared reusable-docker-build
│       └── deploy.yml                   ← Calls shared reusable-ecs-deploy
│
└── payments-service/                    ← Another application repo
    └── .github/workflows/
        ├── ci.yml                       ← Same shared workflows
        └── deploy.yml                   ← Same shared workflows, different inputs
```

Every application repo has tiny workflow files that just pass inputs to shared workflows. The build and deploy logic is written once. Runners in the VPC handle deployments. Composite actions handle repeated setup steps.

---

## File Structure

```
13-cicd-3/
├── README.md                                    ← You are here
├── composite-actions/
│   └── docker-build-scan/
│       └── action.yml                           ← Example composite action
└── .github/
    └── workflows/
        ├── reusable-docker-build.yml            ← Reusable: build, scan, push
        ├── call-reusable-docker-build.yml        ← Example caller workflow
        └── self-hosted-deploy.yml               ← Deploy using self-hosted runner
```

---

## Common Issues

**"Reusable workflow not found"**
The reusable workflow must be in `.github/workflows/` at the repo root (or the ref you specify for cross-repo). It can't be in a subdirectory outside of `.github/workflows/`.

**"Required input not provided"**
Check that every `required: true` input in the reusable workflow has a matching `with:` in the caller. Typos in input names are the usual culprit.

**"Self-hosted runner offline"**
The runner agent crashed or the EC2 instance stopped. SSH in and check `sudo ./svc.sh status`. Common causes: disk full (Docker images), OOM kill, instance terminated by ASG.

**"Job queued but never starts"**
No runner matches the labels in `runs-on`. Check that your runner has all the labels the workflow requires. Labels are AND-matched, not OR-matched.

**"Permission denied in composite action"**
Composite actions run `run:` steps but need `shell: bash` (or `shell: sh`) specified explicitly. Without it, the step fails silently or with a confusing error.

**"Secrets not available in reusable workflow"**
You need to either pass secrets explicitly with `secrets:` or use `secrets: inherit`. The reusable workflow must also declare the secrets it expects in the `on.workflow_call.secrets` block.

---

## Key Takeaways

1. **Reusable workflows = reusable jobs** - define entire pipelines once, call them from any workflow or repo with different inputs
2. **Composite actions = reusable steps** - bundle repeated step sequences into a single clean step
3. **Use both together** - reusable workflows for the pipeline structure, composite actions for common step patterns within them
4. **Self-hosted runners** solve VPC access, compliance, cost and performance problems that GitHub-hosted runners can't
5. **Ephemeral runners** give you self-hosted benefits with GitHub-hosted security (clean environment every run)
6. **Never use self-hosted runners on public repos** - anyone can submit a PR that runs code on your infrastructure
7. **Labels and groups** let you route jobs to the right runners and control access

---

## What's Coming Next

- Multi-environment deployments (dev > staging > prod with approval gates)
- Infrastructure pipelines (Terraform plan/apply in CI/CD)
- Advanced deployment strategies (blue/green, canary)
- GitOps patterns

---

## Resources

- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows)
- [Creating Composite Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action)
- [Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
- [actions-runner-controller (ARC)](https://github.com/actions/actions-runner-controller)
- [Philips Terraform AWS GitHub Runner](https://github.com/philips-labs/terraform-aws-github-runner)
- [GitHub Larger Runners](https://docs.github.com/en/actions/using-github-hosted-runners/using-larger-runners)
