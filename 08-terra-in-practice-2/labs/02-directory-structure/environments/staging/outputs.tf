output "environment" {
  value = "staging"
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

output "test_data_bucket" {
  value = aws_s3_bucket.test_data.id
}
