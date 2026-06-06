variable "aws_region" {
  description = "AWS region for bootstrap resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project slug used in resource names."
  type        = string
  default     = "forge"
}

variable "github_org" {
  description = "GitHub organization or user that owns the Forge repository."
  type        = string
  default     = "akshithkonda1"
}

variable "github_repo" {
  description = "GitHub repository name wired to the deploy OIDC role."
  type        = string
  default     = "Forge"
}

variable "github_environment" {
  description = "GitHub Actions environment allowed to assume the deploy role."
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Additional tags applied to bootstrap resources."
  type        = map(string)
  default = {
    Owner = "Forge"
  }
}