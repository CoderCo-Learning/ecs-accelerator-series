###############################################################################
# GitHub OIDC Bootstrap for ECS CI/CD
#
# This sets up the trust between GitHub Actions and your AWS account.
# Run this ONCE before your pipelines will work.
#
# What it creates:
#   1. GitHub OIDC Identity Provider in IAM
#   2. IAM Role that GitHub Actions can assume
#   3. IAM Policy with exactly the permissions the pipelines need
###############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --------------------------------------------------------------------------
# 1. GitHub OIDC Provider
#
# This tells AWS: "I trust tokens issued by GitHub Actions."
# You only need ONE of these per AWS account, even if you have many repos.
# If you already have one (from another project), you can import it or skip.
# --------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name    = "github-actions-oidc"
    Purpose = "CI/CD pipeline authentication"
  }
}

# --------------------------------------------------------------------------
# 2. IAM Role for GitHub Actions
#
# This is the role your pipeline assumes. The trust policy says:
#   - Only GitHub Actions can assume this role (via OIDC)
#   - Only from YOUR specific repo (not any random GitHub repo)
#   - Only from the branches you allow
#
# The "sub" condition is critical - without it, ANY GitHub repo could
# assume your role. Always scope it to your org/repo.
# --------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Lock this down to your specific repo and branches
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.allowed_subjects
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = {
    Name    = var.role_name
    Purpose = "GitHub Actions CI/CD for ECS"
  }
}

# --------------------------------------------------------------------------
# 3. IAM Policy - Exact Permissions for the Pipeline
#
# This is scoped to ONLY what the pipeline needs:
#   - ECR: login, push/pull images
#   - ECS: register task definitions, update services, describe for waiter
#   - IAM: pass the ECS task execution role (required for register-task-def)
#   - CloudWatch Logs: describe log groups (for task def validation)
#
# No admin access. No wildcards on actions. Least privilege.
# --------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "github_actions_permissions" {
  # ECR - authenticate and push/pull images
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"] # GetAuthorizationToken doesn't support resource-level permissions
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_name}"
    ]
  }

  # ECS - register task definitions and update services
  statement {
    sid    = "ECSDeployment"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
    ]
    resources = ["*"] # ECS actions like RegisterTaskDefinition don't support resource ARNs
  }

  # IAM - pass the ECS task execution role
  # Without this, register-task-definition fails with AccessDenied
  statement {
    sid    = "PassRole"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.ecs_task_execution_role_name}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.ecs_task_role_name}",
    ]
  }

  # CloudWatch Logs - needed for task definition validation
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_actions" {
  name   = "${var.role_name}-policy"
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}
