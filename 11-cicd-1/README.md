# CI/CD Part 1 - The Fundamentals

## What CI/CD Actually Is

CI/CD is automation.

That's it.

Every command you run manually on your laptop:
- `docker build`
- `docker push`
- `terraform plan`
- `terraform apply`
- `npm test`
- `pytest`

CI/CD runs these same commands automatically when code changes.

Nothing magical. Just automation with guardrails.

## The Mental Model

Think of CI/CD as a robot developer who:
- watches your repo
- runs your commands when you push
- tells you if something broke
- deploys if everything passes

You already know the commands.
CI/CD just runs them for you, consistently, every time.

## CI vs CD - The Difference

**CI (Continuous Integration)**
- triggered on every push/PR
- runs tests, linting, security scans
- builds artifacts (Docker images, binaries)
- fast feedback loop

**CD (Continuous Delivery/Deployment)**
- takes the built artifact
- deploys it somewhere (staging, prod)
- can be automatic or require approval

CI = "did I break anything?"
CD = "ship it"

## Anatomy of a Pipeline

A typical pipeline has stages:

```
Push → Build → Test → Scan → Deploy
```

Each stage:
- runs specific commands
- can pass or fail
- blocks the next stage if it fails

This is the "shift left" principle - catch problems early, not in production.

## GitHub Actions Basics

GitHub Actions uses YAML files in `.github/workflows/`.

Basic structure:

```yaml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t my-app .
```

Key concepts:
- **Triggers** (`on:`) - when to run
- **Jobs** - independent units of work
- **Steps** - sequential commands within a job
- **Runners** - machines that execute jobs

## Runners: GitHub-Hosted vs Self-Hosted

**GitHub-Hosted Runners**
- managed by GitHub
- pre-installed tools
- ephemeral (fresh each run)
- free tier limits

**Self-Hosted Runners**
- you manage them (EC2, on-prem)
- access to private networks
- can have custom tools installed
- better for security-sensitive workloads

Why self-hosted matters:
- VPC access (private RDS, internal APIs)
- compliance requirements
- cost control at scale
- faster builds (cached dependencies)

## Reusable Workflows & Custom Actions

Don't repeat yourself.

**Composite Actions**
Bundle multiple steps into one reusable action:

```yaml
# .github/actions/docker-build/action.yml
name: 'Docker Build & Push'
inputs:
  image-name:
    required: true
runs:
  using: 'composite'
  steps:
    - run: docker build -t ${{ inputs.image-name }} .
      shell: bash
```

Think of these like Terraform modules - write once, use everywhere.

**Reusable Workflows**
Share entire workflows across repos:

```yaml
jobs:
  call-workflow:
    uses: org/shared-workflows/.github/workflows/deploy.yml@main
```

## Security Scanning in Pipelines

Every pipeline should scan for vulnerabilities.

Popular tools:
- **Grype** (Anchore) - container and filesystem scanning
- **Clair** (Anchore) - container vulnerability analysis  
- **Trivy** - comprehensive scanner

> ⚠️ **Note on Trivy**: In March 2026, Trivy's GitHub Action was compromised in a supply chain attack. Look at:

> - Pin action versions to specific SHAs
> - Consider alternatives like Grype or Clair
> - Review third-party actions before use

I think there was 1 tag maybe 0.35 that was saved. Or you can use grype.

Example with Grype:

```yaml
- name: Scan image
  uses: anchore/scan-action@v3
  with:
    image: my-app:latest
    fail-build: true
    severity-cutoff: high
```

## Local Testing with `act`

Waiting for GitHub to run your pipeline is slow.

[`act`](https://github.com/nektos/act) runs GitHub Actions locally:

```bash
# Install
brew install act

# Run default workflow
act

# Run specific job
act -j build

# Run on push event
act push
```

Benefits:
- instant feedback
- debug locally
- no commit spam
- faster iteration

Limitations:
- not 100% GitHub parity
- some actions don't work locally
- secrets need manual setup

## Interview Angle: Explaining CI/CD

When asked "explain your CI/CD pipeline" in an interview:

**Structure your answer:**

1. **Trigger**: "Pipeline runs on PR to main and on merge"
2. **Build**: "We build a Docker image, tag with git SHA"
3. **Test**: "Unit tests, integration tests, linting"
4. **Scan**: "Security scan with Grype, fail on high/critical"
5. **Deploy**: "Push to ECR, update ECS task definition"
6. **Rollback**: "Previous image tagged, one-click rollback"

**Key points to hit:**
- immutable artifacts (same image dev→prod)
- environment promotion (not rebuilding)
- automated vs manual gates
- observability (logs, metrics on deploy)

## What's Coming Next

This is Part 1 - foundations.

Future sessions will cover:
- Multi-environment deployments (dev/staging/prod)
- Secrets management in pipelines
- Advanced caching strategies
- GitOps with ArgoCD
- Deployment strategies (blue/green, canary)
- Infrastructure pipelines (Terraform in CI/CD)

## Key Takeaways

1. **CI/CD is just automation** - same commands, triggered automatically
2. **Self-hosted runners** - needed for VPC access and security
3. **Reusable actions** - treat like Terraform modules
4. **Security scanning** - mandatory, use Grype or Clair
5. **Local testing** - use `act` for fast feedback
6. **Pin your versions** - never trust `@latest` in actions

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [act - Local GitHub Actions](https://github.com/nektos/act)
- [Grype - Vulnerability Scanner](https://github.com/anchore/grype)
- [Clair - Container Analysis](https://github.com/quay/clair)
