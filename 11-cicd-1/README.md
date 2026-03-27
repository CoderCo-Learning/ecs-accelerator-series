# CI/CD Part 1 - The Fundamentals

## Life Without CI/CD

Before we talk about what CI/CD is, let's talk about what life looks like without it.

You write some code. You run the tests locally (maybe). You do `docker build`, `docker push`. You SSH into a server or update a task definition by hand. You deploy.

Now multiply that by a team of five.

- someone forgot to run the tests
- someone deployed from a branch that wasn't merged
- someone pushed to prod on a Friday at 5pm
- "it works on my machine"
- two people deployed at the same time and nobody knows what's running

No audit trail. No consistency. Pure vibes-based deployment.

This is the problem CI/CD solves.

## What CI/CD Actually Is

CI/CD is automation. That's it.

Every command you run manually on your laptop - `docker build`, `docker push`, `terraform apply`, `npm test`, `pytest` - CI/CD runs these same commands automatically when code changes.

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

## CI/CD Tools - GitHub Actions Isn't the Only One

There are a *lot* of CI/CD tools out there:

- **Jenkins** - the OG. Released in 2011. Older than some of your colleagues. Governments, banks, massive enterprises - half the world's CI/CD pipelines run on Jenkins. It's the COBOL of CI/CD. Ugly, painful to configure, runs on Java... and absolutely everywhere.
- **GitLab CI** - built into GitLab, `.gitlab-ci.yml`
- **CircleCI** - cloud-native, config-driven
- **Travis CI** - one of the first cloud CI tools, less popular now
- **Harness** - enterprise-grade, big on AI-assisted deployments
- **Concourse** - pipeline-as-code, container-native, used a lot in Cloud Foundry shops
- **Drone** - lightweight, container-first
- **Buildkite** - hybrid model, agents run on your infra
- **Azure DevOps Pipelines** - Microsoft's offering
- **AWS CodePipeline / CodeBuild** - AWS-native CI/CD
- **Tekton** - Kubernetes-native pipelines
- **Argo Workflows** - Kubernetes-native, often paired with Argo CD for GitOps

They all do the same thing: run your commands automatically on code changes. The difference is syntax, where they run and what ecosystem they plug into.

We're using **GitHub Actions** because it's the most accessible - free, built into GitHub, zero infra to manage. But the concepts you learn here transfer directly to any of these tools.

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

## Runners: Where Does Your Pipeline Actually Run?

Your pipeline YAML defines *what* to run. But it needs a machine to run *on* - that's a runner.

**GitHub-Hosted Runners (Free, Public)**
- GitHub gives you runners for free out of the box
- `runs-on: ubuntu-latest` → GitHub spins up a fresh VM, runs your job, destroys it
- pre-installed tools (Docker, Node, Python, etc.)
- ephemeral - clean slate every run, no leftover state
- free tier: 2,000 minutes/month on free plans, more on paid
- these are shared, public infrastructure managed entirely by GitHub

For most open-source projects and simple pipelines, these are all you need. You don't manage anything - just push code and it runs.

**So why would you ever want something else?**

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

## Secrets and Environment Variables

Your pipeline needs credentials - AWS keys, Docker Hub tokens, API keys. **Never hardcode them.**

GitHub Actions has built-in secrets management:

1. Go to your repo > Settings > Secrets and variables > Actions
2. Add a secret (e.g. `AWS_ACCESS_KEY_ID`)
3. Reference it in your workflow:

```yaml
steps:
  - name: Deploy
    env:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    run: aws ecs update-service ...
```

Secrets are masked in logs. GitHub redacts them automatically.

**But storing long-lived keys as secrets is not ideal.** The production-grade approach is to have your pipeline **assume a role** instead.

**AWS** - use OIDC (OpenID Connect). Your GitHub Actions runner requests temporary credentials from AWS STS by assuming an IAM role. These credentials are short-lived (default 1 hour, configurable) and automatically expire. No keys stored anywhere.

**Azure** - similar concept with Workload Identity Federation. Your pipeline authenticates using a federated credential tied to a Service Principal or Managed Identity. Again, no long-lived secrets.

**GCP** - Workload Identity Federation as well. Same pattern.

The theme is the same across all clouds: don't store static credentials. Have the pipeline assume a role, get temporary credentials and let them expire. We'll dig deeper into this in a future session.

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

## Common Gotchas

Things that will bite you early:

- **Forgetting `actions/checkout`** - your workflow runs in an empty VM. If you don't checkout your code, there's nothing there. This is the #1 beginner mistake.
- **YAML indentation** - one space off and your entire pipeline breaks with a cryptic error. Use a YAML linter or your IDE's YAML extension.
- **Using `@latest` or `@main` for actions** - these can change under you. Pin to a specific version or SHA. The Trivy supply chain attack above is exactly what happens when you don't.
- **Hardcoding secrets** - never put credentials in your workflow YAML. Use GitHub Secrets. If it's in your code, it's in your git history forever.
- **Not failing on scan results** - running a security scan that doesn't fail the build on critical vulnerabilities is just a fancy log decorator. Set `fail-build: true`.
- **No branch protection** - if anyone can push to `main` and trigger a deploy, your pipeline is a liability not a guardrail. Set up branch protection rules and require PR reviews.

## What's Coming Next

This is Part 1 - foundations.

Future sessions will cover:
- **Reusable workflows & composite actions** - DRY for pipelines, think Terraform modules
- **Local testing with `act`** - run GitHub Actions on your laptop, instant feedback
- **Multi-environment deployments** (dev/staging/prod)
- **Secrets management** - OIDC, Vault, no more long-lived keys
- **Advanced caching strategies**
- **GitOps in CI/CD**
- **Deployment strategies** (blue/green, canary)
- **Infrastructure pipelines** (Terraform in CI/CD)
- **Interview prep** - how to explain your CI/CD pipeline in an interview

## Key Takeaways

1. **CI/CD is just automation** - same commands you run locally, triggered automatically
2. **Tons of tools, same concept** - Jenkins, GitLab CI, GitHub Actions, Harness - pick one, the concepts transfer
3. **Runners** - GitHub gives you free public runners, self-hosted for VPC access and security
4. **Never hardcode secrets** - use role assumption with temporary credentials
5. **Security scanning is mandatory** - use Grype or Clair, fail on critical
6. **Pin your versions** - never trust `@latest` in actions

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [act - Local GitHub Actions](https://github.com/nektos/act)
- [Grype - Vulnerability Scanner](https://github.com/anchore/grype)
- [Clair - Container Analysis](https://github.com/quay/clair)
