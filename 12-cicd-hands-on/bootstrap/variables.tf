variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "role_name" {
  description = "Name of the IAM role for GitHub Actions"
  type        = string
  default     = "github-actions-ecs-deploy"
}

variable "github_org" {
  description = "Your GitHub organisation or username"
  type        = string
}

variable "github_repo" {
  description = "Your GitHub repository name"
  type        = string
}

variable "allowed_subjects" {
  description = <<-EOT
    List of GitHub OIDC subject claims allowed to assume the role.
    Format: repo:<org>/<repo>:ref:refs/heads/<branch>
            repo:<org>/<repo>:pull_request

    Examples:
      - "repo:CoderCo/my-app:ref:refs/heads/main"     -> only main branch
      - "repo:CoderCo/my-app:pull_request"             -> PR workflows
      - "repo:CoderCo/my-app:*"                        -> any branch (less secure)
  EOT
  type        = list(string)
  default     = []
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository the pipeline pushes to"
  type        = string
}

variable "ecs_task_execution_role_name" {
  description = "Name of the ECS task execution IAM role (the role ECS uses to pull images and write logs)"
  type        = string
  default     = "ecsTaskExecutionRole"
}

variable "ecs_task_role_name" {
  description = "Name of the ECS task IAM role (the role your application code assumes at runtime)"
  type        = string
  default     = "ecsTaskRole"
}
