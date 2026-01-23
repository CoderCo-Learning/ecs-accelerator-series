output "environment" {
  value = "prod"
}

output "bucket_name" {
  value = module.app.bucket_name
}

output "iam_role_arn" {
  value = module.app.iam_role_arn
}

output "ssm_parameters" {
  value = module.app.ssm_parameter_names
}

# Prod-only outputs
output "audit_logs_bucket" {
  value = aws_s3_bucket.audit_logs.id
}

output "backups_bucket" {
  value = aws_s3_bucket.backups.id
}
