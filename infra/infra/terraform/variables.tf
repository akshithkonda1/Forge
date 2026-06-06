variable "aws_region" {
  description = "AWS region for the shared Forge backend."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project slug used in resource names."
  type        = string
  default     = "forge"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "allowed_origins" {
  description = "CORS origins allowed to call the shared backend from web clients."
  type        = list(string)
  default     = ["http://localhost:3000"]
}

variable "skip_aws_provider_checks" {
  description = "Whether to bypass AWS credential/account validation for read-only CI planning."
  type        = bool
  default     = false
}

variable "uploads_bucket_name" {
  description = "Optional override for the Forge uploads bucket name."
  type        = string
  default     = null
  nullable    = true
}

variable "force_destroy_uploads_bucket" {
  description = "Whether Terraform may delete a non-empty uploads bucket."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}

variable "lambda_memory_size" {
  description = "Memory size for the shared Forge backend Lambda."
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout, in seconds, for the shared Forge backend Lambda."
  type        = number
  default     = 15
}

variable "enable_point_in_time_recovery" {
  description = "Whether to enable PITR on the shared Forge DynamoDB table."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
