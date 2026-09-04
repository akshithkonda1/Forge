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
  description = <<-EOT
    Deployment environment name. This is a security control, not a label: the
    Lambda reads it as ENVIRONMENT and uses it to decide whether unsigned
    dev-override tokens are accepted and whether seeded demo data may stand in
    for a user's own health data. Both are enabled for the non-production names
    and disabled for prod/production/staging/stage.

    Deliberately has no default. A value of "dev" inherited by accident is a
    production API that accepts a forged identity, so the choice is made at the
    call site or not at all.
  EOT
  type        = string

  validation {
    # An unrecognised name (a typo like "produciton") would fall outside the
    # backend's production allowlist and be treated as a dev environment, so
    # the set is closed here rather than left to a substring match at runtime.
    condition = contains(
      ["local", "dev", "development", "test", "ci", "stage", "staging", "prod", "production"],
      var.environment
    )
    error_message = "environment must be one of: local, dev, development, test, ci, stage, staging, prod, production."
  }
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

variable "aria_bedrock_enabled" {
  description = "Turn on ARIA's live Claude (Bedrock) reasoning path behind POST /ai/chat. When false, the endpoint serves the deterministic engine. The live path also falls back to deterministic on any Bedrock error."
  type        = bool
  default     = false
}

variable "ai_router_model_3_id" {
  description = "Bedrock model id for the AI router's third slot — the one agentic turns call in when a mode fans out to its own specialists and subagents. Empty keeps ai_router.py's own default (moonshotai.kimi-k2.5). Set per environment so a new tertiary can be proven in staging before production follows."
  type        = string
  default     = ""
}

variable "ai_router_model_3_name" {
  description = "Display name for the third router slot, surfaced in responses and in the client's routing label. Set it alongside ai_router_model_3_id — a name that disagrees with the id is worse than no name, because it makes the transcript claim a model that never answered."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
