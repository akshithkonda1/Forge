variable "aws_region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "us-east-1"
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

variable "tags" {
  description = "Additional tags applied to the state bucket."
  type        = map(string)
  default     = {}
}
