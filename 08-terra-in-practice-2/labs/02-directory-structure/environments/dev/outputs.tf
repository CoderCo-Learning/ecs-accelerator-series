output "environment" {
  value = "dev"
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
