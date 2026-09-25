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

variable "tags" {
  description = "Additional tags applied to the state bucket."
  type        = map(string)
  default     = {}
}
