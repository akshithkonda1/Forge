variable "aws_region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(?:-[a-z]+)+-\\d+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region id (e.g. us-east-1)."
  }
}

variable "skip_aws_provider_checks" {
  description = "Bypass AWS credential/account validation for read-only CI planning."
  type        = bool
  default     = false
}

variable "state_bucket_name" {
  description = "Optional override for the state bucket. Null uses forge-tf-state-{account}."
  type        = string
  default     = null
  nullable    = true
}

variable "state_bucket_deploy_role_arn" {
  description = <<-EOT
    IAM role ARN allowed to s3:GetObject on the state bucket, in addition to
    the account root (root is never denied — a locked-out account cannot
    recover IdP secrets that land in state). When skip_aws_provider_checks is
    true this is unused; the policy uses placeholder ARNs so CI can plan.
  EOT
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub org/repo allowed to assume the deploy role via OIDC (e.g. akshithkonda1/Forge)."
  type        = string
  default     = "akshithkonda1/Forge"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be org/repo."
  }
}

variable "github_oidc_allowed_subs" {
  description = <<-EOT
    token.actions.githubusercontent.com:sub values allowed to assume the
    deploy role. Empty (default) derives repo:var.github_repository locked
    to main and the terraform-prod environment used by the approval-gated
    apply job. Set this only to add extra branches or environments.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for sub in var.github_oidc_allowed_subs :
      can(regex("^repo:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+:", sub))
    ])
    error_message = "github_oidc_allowed_subs entries must be repo:org/repo:… claims."
  }
}

variable "enable_github_oidc" {
  description = "Create the GitHub OIDC provider and deploy role in this account. Default true — IAM is free."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to the state bucket."
  type        = map(string)
  default     = {}
}
