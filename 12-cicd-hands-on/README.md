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

### A Note on Docker Layer Caching

Our build pipeline builds the image from scratch every time. This works but it's slow for large images because Docker re-downloads base layers and re-installs dependencies on every run.

In production, you'd add Docker layer caching to reuse layers from previous builds. GitHub Actions supports this through `docker/build-push-action` with cache backends:

```yaml
- name: Build and push
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

`type=gha` uses GitHub Actions' built-in cache. First build is the same speed. Every build after that reuses unchanged layers and only rebuilds what changed. For a Node or Python app with a `package.json` or `requirements.txt` that doesn't change often, this can cut build times from minutes to seconds.

We're not using this in our pipeline today to keep things simple, but it's one of the first optimisations you'd add in a real project.

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

This is worth repeating from last week because it's the most important architectural decision in this whole setup. If you take one thing from this session, make it this.

#### The Common Mistake

A very common pattern you'll see in tutorials and even in real companies is Terraform managing everything: the ECS cluster, the service, the ALB, the IAM roles AND the task definition including the image tag. On the surface this looks clean. One tool, one source of truth, everything in code.

The problem shows up the moment you actually deploy.

```
Developer pushes code
  → CI builds image, pushes to ECR
  → Someone runs terraform apply to update the task definition
  → Terraform deploys the new image
```

This means every single application deploy requires a full Terraform run. State lock acquired, plan generated, apply executed. For a simple image tag change. That's slow, heavy and creates a bottleneck.

But the real problem is worse than slowness.

#### Two Systems Cannot Manage the Same Resource

Think of ECS as an orchestrator. It manages your containers, your task definitions, your deployments. It expects one system to tell it what to do at any given time. When two systems try to manage the same resource, they fight.

Here's what actually happens:

1. Terraform creates the ECS service with task definition revision 1 (image `my-app:abc123`)
2. CI/CD deploys a new image. It registers task definition revision 2 (image `my-app:def456`) and updates the service
3. Your app is now running revision 2. Everything works
4. A week later, someone needs to change a security group. They run `terraform plan`
5. Terraform says: "The ECS service is using task definition revision 2 but my state says it should be revision 1. I'm going to revert it."
6. `terraform apply` rolls your app back to the old image. Your deployment is undone

This is called **drift**. Terraform's state file thinks the service should point at revision 1 because that's what Terraform last applied. CI/CD updated it to revision 2 outside of Terraform's knowledge. Now they're fighting over who controls the task definition and Terraform wins because Terraform enforces state.

This gets worse with teams. Imagine five developers deploying through CI/CD throughout the day while an infrastructure engineer runs `terraform apply` for an unrelated VPC change. Every `terraform apply` potentially reverts the latest deployment. Nobody realises until someone checks why the app is running last week's code.

#### The Right Way: Clear Ownership Boundaries

The fix is simple. Give each tool its own domain and don't let them overlap.

**Terraform (IaC) owns infrastructure.** The things that change rarely and need to be provisioned once:
- ECS cluster
- ECS service configuration (desired count, deployment settings, load balancer config)
- ALB, listeners, target groups
- IAM roles and policies
- Security groups
- VPC, subnets, networking
- The *initial* task definition (to bootstrap the service)

**CI/CD owns the application lifecycle.** The things that change on every push:
- Building the Docker image
- Tagging with the commit SHA
- Registering a new task definition revision with the updated image
- Updating the ECS service to use the new revision
- Monitoring the deployment

Terraform sets up the stage. CI/CD runs the show.

#### lifecycle ignore_changes

To make this work, you need to tell Terraform to stop managing the parts that CI/CD handles. Terraform has a `lifecycle` block with `ignore_changes` for exactly this:

```hcl
resource "aws_ecs_service" "app" {
  name            = "my-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2

  # CI/CD manages the task definition after initial creation.
  # Without this, terraform apply reverts every deployment CI/CD has done.
  lifecycle {
    ignore_changes = [task_definition]
  }
}
```

What this does: Terraform creates the service with the initial task definition. After that, it ignores any changes to the `task_definition` attribute. When CI/CD registers revision 5 and updates the service, Terraform doesn't see it as drift. `terraform plan` won't try to revert it.

You might also want to ignore `desired_count` if you're using auto-scaling:

```hcl
lifecycle {
  ignore_changes = [task_definition, desired_count]
}
```

Without this, Terraform would revert your auto-scaled count back to whatever is hardcoded in the Terraform config every time someone runs `terraform apply`.

#### What About the Task Definition Resource?

You might wonder: should Terraform manage `aws_ecs_task_definition` at all?

Yes, but only for the initial creation. Terraform creates revision 1 with a placeholder or initial image. After that, CI/CD takes over and registers new revisions directly through the AWS API. The task definition revisions created by CI/CD don't exist in Terraform state and that's fine. They don't need to.

If you need to change something structural about the task definition (CPU, memory, log configuration, IAM role), you update it in Terraform and apply. CI/CD will pick up those changes on the next deploy because it fetches the *current* task definition from ECS, not from a file.

---

### Production Quirks Worth Knowing

These are things that will catch you in a real production environment. They're not beginner topics but thinking about them now will save you pain later.

#### Deployment Circuit Breaker

By default, if your new task definition is broken (bad image, missing env var, crash loop), ECS just keeps trying to start it. Forever. Your pipeline hangs waiting for stability. The old tasks eventually get drained. Your app goes down.

Enable the deployment circuit breaker in your ECS service (in Terraform):

```hcl
deployment_circuit_breaker {
  enable   = true
  rollback = true
}
```

With this enabled, ECS detects that new tasks keep failing health checks and automatically rolls back to the previous working task definition. Your pipeline will report a failure (the wait step sees the rollback) but your app stays up.

#### Health Check Timing

ECS uses ALB health checks to decide if new tasks are healthy. If your health check is misconfigured, ECS will kill perfectly good containers.

Common issues:
- **Health check path is wrong.** You set `/health` but your app serves it at `/healthz`. ECS sees 404, marks the task as unhealthy, kills it
- **Health check interval is too short.** Your app takes 15 seconds to start but the health check expects a response in 5 seconds. The task gets killed before it's ready
- **Health check threshold is too strict.** One slow response and the task is marked unhealthy

In your ALB target group (in Terraform):

```hcl
health_check {
  path                = "/health"
  interval            = 30
  timeout             = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
  matcher             = "200"
}
```

Give your app time to start. `healthy_threshold: 2` means two consecutive healthy responses before the task is considered up. `unhealthy_threshold: 3` means three consecutive failures before it's killed. Don't make these too aggressive.

#### Graceful Shutdown

During a rolling deploy, ECS sends SIGTERM to old containers before killing them. If your app doesn't handle SIGTERM properly, in-flight requests get dropped. Users see 502 errors from the ALB.

Your app needs to:
1. Catch SIGTERM
2. Stop accepting new connections
3. Finish processing in-flight requests
4. Close database connections
5. Flush logs
6. Exit cleanly

The `stopTimeout` setting (default 30 seconds) controls how long ECS waits between SIGTERM and SIGKILL. If your app takes longer than 30 seconds to shut down gracefully, increase this in your task definition.

Most web frameworks handle SIGTERM out of the box (Express, Flask, Go's http.Server with Shutdown). But if you're running raw processes or custom entrypoints, you need to handle it yourself.

#### Rolling Deploy Settings

Two settings on your ECS service control how aggressive deploys are:

- `minimumHealthyPercent: 100` + `maximumPercent: 200` - keep all old tasks running, start new ones alongside. Zero downtime but you briefly pay for double the tasks during the deploy window
- `minimumHealthyPercent: 50` + `maximumPercent: 100` - kill half the old tasks first, then start new ones. Uses fewer resources but you run at reduced capacity during the deploy

For production, use 100/200. The extra cost during deploy (usually a few minutes) is worth guaranteed zero downtime. For dev/staging, 50/100 is fine to save money.

#### ECS Exec for Debugging

When a deploy goes wrong and you need to debug a running container, `ecs exec` lets you shell into it:

```bash
aws ecs execute-command \
  --cluster my-cluster \
  --task <task-id> \
  --container app \
  --interactive \
  --command "/bin/sh"
```

This requires the ECS Exec feature to be enabled on your service and the task role to have SSM permissions. Set this up before you need it, not during an incident at 2am.

#### Rollback

Rollback with commit SHA tagging is simple: redeploy the previous SHA.

If revision 5 (`my-app:def456`) broke something, find the last known good commit SHA and trigger a new deploy with that image. The pipeline registers revision 6 pointing at the old image. ECS rolls forward to revision 6 which runs the old code. You're not actually "rolling back" in ECS terms. You're rolling forward to a new revision that happens to use a previous image.

```bash
# Find the previous task definition's image
aws ecs describe-task-definition --task-definition my-service:4 \
  --query 'taskDefinition.containerDefinitions[0].image' --output text

# Trigger a deploy with that image (or just rerun the pipeline for that commit)
```

The fastest approach is usually to revert the commit in git and let the pipeline do its thing. The new commit triggers a build with the reverted code, which produces an image, which gets deployed. Fully automated rollback through the same pipeline.

---

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
