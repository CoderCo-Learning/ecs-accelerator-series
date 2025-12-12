output "efs_id" {
  value = aws_efs_file_system.app_efs.id
}

output "efs_dns_name" {
  value = aws_efs_file_system.app_efs.dns_name
}