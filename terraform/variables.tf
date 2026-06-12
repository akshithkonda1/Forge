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

variable "cognito_domain_prefix" {
  description = "Hosted UI domain prefix (must be globally unique). Defaults to <name_prefix>-<account>."
  type        = string
  default     = null
  nullable    = true
}

variable "web_callback_urls" {
  description = "Allowed OAuth redirect URIs for the web app Hosted UI sign-in."
  type        = list(string)
  default     = ["http://localhost:3000/auth/callback"]
}

variable "web_logout_urls" {
  description = "Allowed sign-out redirect URIs for the web app."
  type        = list(string)
  default     = ["http://localhost:3000/"]
}

variable "ios_callback_urls" {
  description = "Allowed OAuth redirect URIs for the iOS app (custom scheme for ASWebAuthenticationSession)."
  type        = list(string)
  default     = ["forge://auth/callback"]
}

variable "ios_logout_urls" {
  description = "Allowed sign-out redirect URIs for the iOS app."
  type        = list(string)
  default     = ["forge://auth/signout"]
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

variable "force_destroy_artifacts_bucket" {
  description = "Whether Terraform may delete a non-empty Lambda artifacts bucket."
  type        = bool
  default     = false
}

variable "enable_self_healing" {
  description = "Enable AWS-native self-healing (health probes, alarms, S3 artifact redeploy). No Kubernetes required."
  type        = bool
  default     = true
}

variable "health_check_interval_minutes" {
  description = "How often the healer Lambda probes /health and emits metrics."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_interval_minutes >= 1 && var.health_check_interval_minutes <= 60
    error_message = "health_check_interval_minutes must be between 1 and 60."
  }
}

variable "health_check_timeout_seconds" {
  description = "Timeout for the healer Lambda's /health HTTP probe."
  type        = number
  default     = 10
}

variable "alert_email" {
  description = "Optional email address for SNS ops alerts when self-healing triggers."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_terra_self_healing" {
  description = "Enable scheduled Terra integration health checks and stale-connection repair on the API Lambda."
  type        = bool
  default     = true
}

variable "terra_self_heal_interval_minutes" {
  description = "How often EventBridge triggers Terra self-healing on the backend Lambda."
  type        = number
  default     = 60

  validation {
    condition     = var.terra_self_heal_interval_minutes >= 15 && var.terra_self_heal_interval_minutes <= 1440
    error_message = "terra_self_heal_interval_minutes must be between 15 and 1440."
  }
}

variable "ops_self_heal_token" {
  description = "Optional bearer token for manual POST /integrations/terra/self-heal and /self-integrate."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
