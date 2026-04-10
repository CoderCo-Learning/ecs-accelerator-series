# CI/CD Part 2 - Hands-On: Building the Pipeline

## The Journey So Far

```
Episode 1-4:   You learned to containerise
Episode 5:     You pushed to ECR
Episode 6-8:   You learned Terraform foundations
Episode 9:     You deployed ECS manually (ClickOps)
Episode 10:    You rebuilt it all as Terraform
Episode 11:    You learned CI/CD concepts - what, why, how it works
```

Last week was theory. This week we look at more practical stuff.

By the end of this session you'll understand how to create:

- An OIDC trust between GitHub Actions and AWS (no stored keys)
- A CI pipeline that builds, scans and pushes your Docker image
- A CD pipeline that deploys to ECS automatically
- A PR pipeline that scans for vulnerabilities before code merges
- A reusable workflow template you can apply anywhere

---

## Part 1: The Bootstrap - OIDC Trust

Before your pipeline can do anything with AWS, it needs to authenticate. In Episode 11 we talked about why you shouldn't store long-lived AWS keys. Here's where we set up the alternative.

### What is OIDC?

OIDC (OpenID Connect) lets GitHub Actions prove its identity to AWS without any stored credentials.

The flow:

```
GitHub Actions Runner                         AWS
       │                                       │
       │  1. "I'm a workflow in org/repo"      │
       ├──────────────────────────────────────►│
       │                                       │  2. AWS checks: "Do I trust GitHub?
       │                                       │      Is this repo allowed?"
       │  3. Here are temporary credentials    │
       │◄──────────────────────────────────────┤
       │     (expire in 1 hour)                │
       │                                       │
       │  4. Uses temp creds for ECR, ECS      │
       ├──────────────────────────────────────►│
       │                                       │
```

No keys stored in GitHub Secrets. No keys in your code. No keys to rotate. Credentials are issued on-demand and expire automatically.

### Setting Up the Trust

The `bootstrap/` directory contains the Terraform to set up this trust. It creates three things:

1. **GitHub OIDC Identity Provider** - tells AWS "I trust tokens from GitHub Actions"
2. **IAM Role** - the role your pipeline assumes, scoped to your specific repo
3. **IAM Policy** - the exact permissions the pipeline needs (ECR push, ECS deploy)

### Running the Bootstrap

```bash
cd bootstrap/

# Copy the example and fill in your values
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your repo details
# IMPORTANT: get the allowed_subjects right - this controls who can assume the role
```

Your `terraform.tfvars` should look like:

```hcl
aws_region  = "eu-west-2"
github_org  = "your_user"
github_repo = "your-ecs-app"

allowed_subjects = [
  "repo:your_user/your-ecs-app:ref:refs/heads/main",
  "repo:your_user/your-ecs-app:pull_request",
]

ecr_repository_name         = "my-app"
ecs_task_execution_role_name = "ecsTaskExecutionRole"
ecs_task_role_name           = "ecsTaskRole"
```

Then apply:

```bash
terraform init
terraform plan    # Review what's being created
terraform apply
```

The output gives you the Role ARN. You need this for the next step.

### Adding the Role ARN to GitHub

After `terraform apply`, take the `role_arn` output and add it to your GitHub repo:

1. Go to your repo on GitHub
2. Settings > Secrets and variables > Actions
3. New repository secret
4. Name: `AWS_ROLE_ARN`
5. Value: the ARN from the Terraform output (e.g. `arn:aws:iam::123456789012:role/github-actions-ecs-deploy`)

This is the **only** secret your pipeline needs. And it's not even a credential - it's just telling the pipeline which role to assume. The actual authentication happens via OIDC.

### The Trust Policy - why we need this??

Look at the trust policy in `bootstrap/main.tf`. The critical part is the `sub` condition:

```hcl
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values   = var.allowed_subjects
}
```

This says: "Only GitHub Actions workflows running in **this specific repo** on **these specific branches** can assume this role."

Without this condition, **any** GitHub repository could assume your IAM role. That would be very bad. Always scope your OIDC trust to the minimum.

### The Permissions - Least Privilege

The IAM policy gives the pipeline exactly what it needs and nothing more:

| Permission | Why |
|------------|-----|
| `ecr:GetAuthorizationToken` | Login to ECR |
| `ecr:PutImage`, `ecr:UploadLayerPart`, etc. | Push images |
| `ecs:RegisterTaskDefinition` | Create new task definition revisions |
| `ecs:UpdateService` | Trigger rolling deployments |
| `ecs:DescribeServices`, `ecs:DescribeTasks` | Wait for deployment to stabilise |
| `iam:PassRole` | Let ECS use the task execution role |
| `logs:DescribeLogGroups` | Task definition validation |

No `*` on actions. No admin access. If the pipeline doesn't need it, it shouldn't have it.

---

## Part 2: The CI Pipeline - Build & Push

File: `.github/workflows/build.yml`

This pipeline triggers on every push to `main` and does:

```
Checkout > Build > Container Scan (Grype) > Auth (OIDC) > Push to ECR/DockerHub/GHCR etc
```

### The Permissions Block

```yaml
permissions:
  id-token: write   # Required for OIDC authentication with AWS
  contents: read     # Required for actions/checkout
```

This is the one that catches everyone out. Without `id-token: write`, the OIDC step silently fails. Your pipeline will error with a cryptic "Not authorized to perform sts:AssumeRoleWithWebIdentity" message. It's not an IAM problem - it's a workflow permissions problem.

By default, GitHub Actions workflows have `contents: read` only. The moment you set `permissions:` explicitly, you lose all defaults and must declare everything you need.

### Image Tagging

```yaml
docker build -t ${{ env.ECR_REPOSITORY }}:${{ github.sha }} .
```

We tag with `github.sha` - the full 40-character commit hash. This is immutable. That image will always map to that exact commit. You can look at any running container, check its image tag and know exactly what code is in it.

We also push a `latest` tag for convenience, but the SHA tag is the source of truth.

### Concurrency

```yaml
concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: true
```

If two commits land on `main` within seconds, we don't need two builds racing. The newer commit cancels the older one. Latest code wins.

---

## Part 3: The CD Pipeline - Deploy to ECS

File: `.github/workflows/deploy.yml`

This pipeline triggers **after** the build pipeline succeeds:

```yaml
on:
  workflow_run:
    workflows: ["CI - Build & Push"]
    types: [completed]
    branches: [main]
```

The deploy pipeline has two jobs. The first job handles OIDC authentication and builds the image URI. The second job calls the **reusable ECS deploy workflow** (more on that in Part 5) which handles the actual task definition update and service rollout. This means the deploy logic is written once and can be called by any workflow in the repo.

```yaml
jobs:
  auth:
    # OIDC auth, ECR login, build the image URI
    ...
    outputs:
      image: ${{ steps.image.outputs.uri }}

  deploy:
    needs: auth
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: my-cluster
      service: my-service
      container_name: app
      image: ${{ needs.auth.outputs.image }}
```

If you had multiple services (api, worker, cron), you'd call the reusable workflow once per service with different inputs. One deploy pipeline, many services.

### Why CI/CD Owns Deployments, Not Terraform

This is worth repeating from last week because it's the most important architectural decision in this whole setup.

**The wrong way:**
```
Developer pushes code
  → CI builds image, pushes to ECR
  → Someone runs terraform apply to update the task definition
  → Terraform deploys the new image
```

Problems:
- Every deploy requires a Terraform run (slow: state lock, plan, apply)
- Terraform drift: CI/CD updated the image, now `terraform plan` wants to revert it
- Two systems fighting over the same resource

**The right way:**
```
Developer pushes code
  → CI builds image, pushes to ECR
  → CD pipeline updates the task definition directly via AWS API
  → CD pipeline triggers ECS rolling deployment
  → No Terraform involved in application deploys
```

**Terraform owns infrastructure.** The cluster, the service, the ALB, IAM roles, security groups, the *initial* task definition.

**CI/CD owns the application lifecycle.** New image → new task definition revision → rolling deploy.

In your Terraform, add `ignore_changes` so it doesn't fight with CI/CD:

```hcl
resource "aws_ecs_service" "app" {
  # ... your service config ...

  # Let CI/CD manage the task definition - don't revert on terraform apply
  lifecycle {
    ignore_changes = [task_definition]
  }
}
```

### How the Deploy Works

The deploy pipeline does this:

1. **Fetches the current task definition** from ECS (not from a file in git)
2. **Updates the image tag** to the new commit SHA
3. **Registers a new task definition revision** (revisions are immutable - v1, v2, v3...)
4. **Updates the ECS service** to use the new revision
5. **Waits for stability** - ECS rolls out new tasks and drains old ones

```bash
# This is what the pipeline does under the hood
aws ecs describe-task-definition --task-definition my-service > task-def.json
# ... update the image in the JSON ...
aws ecs register-task-definition --cli-input-json file://updated-task-def.json
aws ecs update-service --cluster my-cluster --service my-service --task-definition new-arn
aws ecs wait services-stable --cluster my-cluster --services my-service
```

The `wait services-stable` step is critical. Without it, your pipeline says "success" immediately after calling `update-service`, even if the new tasks crash on startup. The wait watches the deployment and only succeeds when new tasks are healthy.

### Deploy Concurrency

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: true
```

Only one deployment at a time. If two builds complete back-to-back, the second deploy cancels the first. You always deploy the latest successful build.

---

## Part 4: The PR Pipeline - Scan Before Merge

File: `.github/workflows/pr-scan.yml`

This is your gatekeeper. Every pull request:

1. Builds the Docker image (verifies it builds)
2. Scans with Grype (fails on high/critical CVEs)

```yaml
on:
  pull_request:
    branches: [main]
```

Notice this pipeline has **no AWS permissions**. It doesn't need `id-token: write` because it's not pushing to ECR or deploying. It just builds and scans locally on the runner. This keeps PR pipelines fast and reduces the blast radius.

### Branch Protection

For this to actually block bad code, you need branch protection rules:

1. Go to your repo > Settings > Branches
2. Add rule for `main`
3. Check "Require status checks to pass before merging"
4. Search for "Build & Scan" and add it as a required check
5. Check "Require pull request reviews before merging"

Now:
- No one can push directly to `main`
- PRs must pass the scan before merging
- You have a forcing function for code quality

---

## Part 5: Reusable Workflows

Files:
- `.github/workflows/reusable-greeting.yml` - simple template to show the pattern
- `.github/workflows/call-reusable.yml` - how to call it
- `.github/workflows/reusable-ecs-deploy.yml` - real-world example used by our deploy pipeline

Think of reusable workflows like Terraform modules. Define once, use everywhere.

> **Important:** GitHub Actions only reads workflows from the repo root's `.github/workflows/` directory. The workflow files inside `12-cicd-hands-on/.github/workflows/` are reference examples. To actually run them, they must be in the root `.github/workflows/`. We've already copied them there for this repo.

### Defining a Reusable Workflow

The key difference is the trigger:

```yaml
on:
  workflow_call:       # <-- This makes it reusable
    inputs:
      name:
        required: true
        type: string
```

`workflow_call` means "I can't run on my own, someone has to call me."

### Calling a Reusable Workflow

```yaml
jobs:
  call-greeting:
    uses: ./.github/workflows/reusable-greeting.yml
    with:
      name: "CoderCo"
      environment: "dev"
```

Notice the job uses `uses:` instead of `runs-on:` + `steps:`. The entire job delegates to the reusable workflow.

### Cross-Repo Reusable Workflows

You can call workflows from other repos too:

```yaml
jobs:
  deploy:
    uses: CoderCo/shared-workflows/.github/workflows/ecs-deploy.yml@main
    with:
      cluster: my-cluster
      service: my-service
    secrets:
      AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}
```

This is powerful for organisations. You define your standard build/deploy pipelines in a shared repo and every team's repo calls them. One place to update and every repo gets the fix.

### Real-World Example: Reusable ECS Deploy

The greeting example is for learning. The real payoff is `reusable-ecs-deploy.yml` which our deploy pipeline actually uses. It accepts inputs for cluster, service, container name and image, then handles the entire deploy flow:

```yaml
jobs:
  deploy:
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: my-cluster
      service: my-service
      container_name: app
      image: 123456.dkr.ecr.eu-west-1.amazonaws.com/my-app:abc123
```

Inside the reusable workflow, it fetches the current task definition, cleans the metadata, swaps the image, registers a new revision, updates the service and waits for stability. All the logic from Part 3, packaged as a reusable module.

If you had three microservices, your deploy pipeline would call it three times:

```yaml
jobs:
  deploy-api:
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: production
      service: api
      container_name: api
      image: ${{ needs.auth.outputs.api_image }}

  deploy-worker:
    uses: ./.github/workflows/reusable-ecs-deploy.yml
    with:
      cluster: production
      service: worker
      container_name: worker
      image: ${{ needs.auth.outputs.worker_image }}
```

Same deploy logic, no copy-paste.

### The Greeting Example

We've also included a simple greeting workflow to demonstrate the pattern. Run it manually:

1. Go to Actions tab in your repo
2. Find "Test - Call Reusable Greeting"
3. Click "Run workflow"
4. Enter a name and run it

Watch how it calls the reusable workflow twice (once for dev, once for prod) and then runs a summary job after both complete.

---

## Part 6: Secrets and Environment Variables

### When You Change a Secret

If you update a secret in GitHub (Settings > Secrets and variables > Actions):

- **Running workflows are NOT affected.** Secrets are injected at the start of the run. If you change a secret mid-run, the running workflow still has the old value.
- **Next run picks up the new value.** The next time the workflow triggers, it gets the updated secret.
- **No restart needed.** Unlike some CI tools, GitHub Actions doesn't cache secrets between runs.

### When You Change an Environment Variable

Environment variables in workflows come from two places:

**1. Workflow-level `env:` block (in the YAML)**

```yaml
env:
  AWS_REGION: eu-west-1
  ECR_REPOSITORY: my-app
```

These are hardcoded in the workflow file. To change them, you commit a change to the YAML. The change takes effect on the next run that uses the updated file.

**2. GitHub Environment variables (in the UI)**

Settings > Environments > (your environment) > Environment variables

These work like secrets but aren't masked. Same behaviour: running workflows keep the old value, next run gets the new value.

### When You Change ECS Task Definition Environment Variables

This is separate from pipeline env vars. If your **application** needs new environment variables (e.g. a new API key, a feature flag):

**Option A: Update via the pipeline (recommended)**

Your task definition JSON has the environment variables. Update the task definition template and let CI/CD deploy it. This is auditable - the change is in git.

**Option B: Update via Terraform**

If Terraform manages the initial task definition, add the new env var there and run `terraform apply`. Remember: if CI/CD has since deployed a newer task definition revision, Terraform might try to revert it unless you have `ignore_changes` set correctly.

**Option C: Manual update in AWS console**

You can update the task definition in the AWS console and create a new revision. Then update the service to use it. This works but leaves no audit trail. Not recommended for production.

**The golden rule:** Treat environment variables as config and config should live in code (git). Whether that's in your task definition template, Terraform or a dedicated config file - it should be versioned and reviewable.

### Secrets in ECS Task Definitions

For secrets your application needs at runtime (database passwords, API keys), don't put them in the task definition as plain text environment variables. Use AWS Secrets Manager or SSM Parameter Store:

```json
"secrets": [
  {
    "name": "DATABASE_URL",
    "valueFrom": "arn:aws:secretsmanager:eu-west-1:123456789:secret:my-app/db-url"
  }
]
```

ECS pulls the secret at container startup. The value never appears in the task definition, CloudFormation or Terraform state. If you need to rotate a secret, update it in Secrets Manager and restart the tasks - the new containers pick up the new value.

---

## Putting It All Together

Here's the full flow with everything wired up:

```
Developer creates a PR
  │
  ├─► PR Pipeline runs
  │     ├── Build Docker image
  │     ├── Grype scan (fail on high/critical)
  │     └── ✅ or ❌ status check on PR
  │
  ▼
PR is approved and merged to main
  │
  ├─► Build Pipeline runs
  │     ├── Build Docker image
  │     ├── Tag with commit SHA
  │     ├── Grype scan
  │     ├── OIDC auth to AWS
  │     └── Push to ECR
  │
  ├─► Deploy Pipeline triggers (after build succeeds)
  │     ├── OIDC auth to AWS
  │     ├── Fetch current task definition
  │     ├── Update image to new SHA
  │     ├── Register new task definition revision
  │     ├── Update ECS service
  │     └── Wait for stability
  │
  ▼
New version is live
```

Every step is automated. Every image is scanned. Every deploy is traceable to a specific commit. No manual steps. No stored credentials.

---

## File Structure

```
12-cicd-hands-on/
├── README.md                              ← You are here
├── bootstrap/
│   ├── main.tf                            ← OIDC provider + IAM role + policy
│   ├── variables.tf                       ← Configuration inputs
│   ├── outputs.tf                         ← Role ARN output
│   └── terraform.tfvars.example           ← Copy and fill in your values
└── .github/
    └── workflows/
        ├── build.yml                      ← CI: build, scan, push to ECR
        ├── deploy.yml                     ← CD: deploy to ECS (calls reusable)
        ├── pr-scan.yml                    ← PR: build + Grype scan
        ├── reusable-ecs-deploy.yml        ← Reusable: ECS task def + deploy logic
        ├── reusable-greeting.yml          ← Reusable: simple greeting template
        └── call-reusable.yml              ← Example: calling the reusable workflow
```

These workflow files are reference copies. The runnable versions live in the repo root's `.github/workflows/` directory since that's where GitHub Actions looks for them.

---

## Common Issues You'll Hit

**"Not authorized to perform sts:AssumeRoleWithWebIdentity"**
You forgot `permissions: id-token: write` in your workflow. Or your `allowed_subjects` in the bootstrap don't match your repo/branch.

**"Unable to locate credentials"**
The `configure-aws-credentials` step isn't before your AWS commands. Or it failed silently. Check the step output.

**"AccessDeniedException when calling RegisterTaskDefinition"**
Your IAM policy is missing `iam:PassRole` for the ECS task execution role. The pipeline needs permission to say "ECS, use this role" when registering task definitions.

**Deploy "succeeds" but app is down**
Your health check path is wrong or too aggressive. Check your ALB target group health check settings. ECS waits for health checks to pass before draining old tasks - if the check never passes, the old tasks get killed and the new ones keep restarting.

**Grype fails with vulnerabilities you can't fix**
If the CVE is in a base image and there's no patched version yet, you have two options: update your base image to a newer version that has the fix, or temporarily lower the severity cutoff. Document why and create a ticket to revisit.

**Pipeline works on main but fails on PRs (or vice versa)**
Check your `on:` triggers and `permissions:` block. PRs and pushes have different GitHub contexts. Also check your OIDC `allowed_subjects` - if you only allowed `ref:refs/heads/main`, PR workflows can't assume the role (which is correct for the PR scan pipeline since it doesn't need AWS access).

---

## Key Takeaways

1. **OIDC eliminates stored credentials** - no AWS keys in GitHub Secrets, temporary credentials only
2. **Separate build and deploy** - CI builds the artifact, CD deploys it, they're independent stages
3. **CI/CD owns application deploys, Terraform owns infrastructure** - don't fight over the task definition
4. **Scan on PRs, block on failures** - Grype + branch protection = vulnerabilities don't reach main
5. **Tag with commit SHA** - every image is traceable, every deploy is auditable, rollback is trivial
6. **Reusable workflows = DRY pipelines** - define once, call from any workflow or repo
7. **Permissions matter** - `id-token: write` for OIDC, least privilege on IAM, branch protection on main

---

## What's Coming Next

- Multi-environment deployments (dev → staging → prod with approvals)
- Infrastructure pipelines (Terraform plan/apply in CI/CD)
- Advanced deployment strategies (blue/green, canary)
- Local pipeline testing with `act`
- GitOps patterns

---

## Resources

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Grype - Vulnerability Scanner](https://github.com/anchore/grype)
- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows)
- [AWS ECS Deploy Task Definition Action](https://github.com/aws-actions/amazon-ecs-deploy-task-definition)
- [GitHub Actions Permissions](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
