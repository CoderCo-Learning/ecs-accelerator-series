output "environment" {
  description = "Current workspace/environment"
  value       = terraform.workspace
}

output "bucket_name" {
  description = "App bucket name"
  value       = aws_s3_bucket.app.id
}

output "bucket_arn" {
  description = "App bucket ARN"
  value       = aws_s3_bucket.app.arn
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.app.arn
}

output "ssm_parameters" {
  description = "SSM parameter names"
  value       = [for p in aws_ssm_parameter.config : p.name]
}

output "logs_bucket" {
  description = "Logs bucket (staging/prod only)"
  value       = length(aws_s3_bucket.logs) > 0 ? aws_s3_bucket.logs[0].id : "N/A - dev environment"
}

output "config_summary" {
  description = "Current environment configuration"
  value = {
    environment   = terraform.workspace
    versioning    = local.config.enable_versioning
    log_retention = local.config.log_retention
  }
}
