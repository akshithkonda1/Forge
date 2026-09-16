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
  description = <<-EOT
    Kill-switch for live Amazon Bedrock. Default false: POST /ai/chat stays on the
    deterministic engine, POST /ai/router returns 503, and BedrockGateway never
    calls Converse. Dummy-offline and live-API-no-Bedrock must keep this false
    (no token spend). Grok 4.6 is on Bedrock; this flag is an access gate, not a
    statement that the model is missing. Turning it on still needs account
    model-access enablement (Anthropic Marketplace / FTU, xAI) and a geo/global
    runtime profile from us-east-1 — see ROADMAP_IAC_READINESS.md. IAM in this
    module already allows anthropic.* and Grok CRIS (us.xai.* / global.xai.*).
  EOT
  type        = bool
  default     = false
}

variable "ai_router_model_1_id" {
  description = <<-EOT
    Bedrock model id for router slot 1. Empty keeps anthropic.claude-sonnet-4-6
    (ai_router.default_models()). Inert while aria_bedrock_enabled is false.
    A later Sonnet 5 swap is us.anthropic.claude-sonnet-5 or
    global.anthropic.claude-sonnet-5 on bedrock-runtime from us-east-1
    (In-Region runtime is not supported — official Sonnet 5 card).
  EOT
  type        = string
  default     = ""
}

variable "ai_router_model_1_name" {
  description = "Display name for router slot 1. Set it alongside ai_router_model_1_id — a name that disagrees with the id is worse than no name."
  type        = string
  default     = ""
}

variable "ai_router_model_2_id" {
  description = <<-EOT
    Bedrock model id for router slot 2. Empty keeps anthropic.claude-opus-4-7
    (ai_router.default_models()). Inert while aria_bedrock_enabled is false.
    A later Opus 5 swap is us.anthropic.claude-opus-5 or
    global.anthropic.claude-opus-5 on bedrock-runtime from us-east-1.
  EOT
  type        = string
  default     = ""
}

variable "ai_router_model_2_name" {
  description = "Display name for router slot 2. Set it alongside ai_router_model_2_id — a name that disagrees with the id is worse than no name."
  type        = string
  default     = ""
}

variable "ai_router_model_3_id" {
  description = <<-EOT
    Bedrock model id for the AI router's third slot. Empty keeps the Lambda
    fallback global.xai.grok-4.6 — the Grok 4.6 Global CRIS id on
    bedrock-runtime (official model card; US Geo is us.xai.grok-4.6; mantle
    in-Region id is xai.grok-4.6). Inert while aria_bedrock_enabled is false.
    Do not set Grok 4.3 here (mantle In-Region only). A name that disagrees
    with the id is worse than no name.
  EOT
  type        = string
  default     = ""
}

variable "ai_router_model_3_name" {
  description = "Display name for the third router slot, surfaced in responses and in the client's routing label. Set it alongside ai_router_model_3_id — a name that disagrees with the id is worse than no name, because it makes the transcript claim a model that never answered."
  type        = string
  default     = ""
}

variable "enable_spend_guard" {
  description = <<-EOT
    Create an optional monthly AWS Budgets COST budget. Default false: Dummy-
    offline and an apply with module defaults create no budget resource.
    Enable only on a live applied account. First two AWS Budgets are free;
    notifications need spend_guard_notification_email.
  EOT
  type        = bool
  default     = false
}

variable "spend_guard_limit_usd" {
  description = "Monthly USD limit for the optional spend-guard budget. Unused while enable_spend_guard is false."
  type        = number
  default     = 5
}

variable "spend_guard_notification_email" {
  description = "If set with enable_spend_guard, subscribe this address at 80% actual spend. Empty skips notifications."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
