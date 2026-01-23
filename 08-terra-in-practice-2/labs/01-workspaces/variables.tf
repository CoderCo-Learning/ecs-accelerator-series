variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "demo-app"
}

variable "allowed_workspaces" {
  description = "Allowed workspace names"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}
