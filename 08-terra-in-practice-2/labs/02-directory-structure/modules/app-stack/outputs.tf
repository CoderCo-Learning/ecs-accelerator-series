output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.app.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.app.arn
}

output "iam_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.app.name
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.app.arn
}

output "ssm_parameter_names" {
  description = "Created SSM parameter names"
  value       = [for p in aws_ssm_parameter.config : p.name]
}

output "random_suffix" {
  description = "Random suffix for unique naming"
  value       = random_id.suffix.hex
}
