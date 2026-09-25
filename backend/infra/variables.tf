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
  description = <<-EOT
    Override CloudWatch log retention in days. Null (the default) uses 30 in
    prod-like environments and 14 everywhere else, including the CI plan.
  EOT
  type        = number
  default     = null
  nullable    = true
}

variable "lambda_memory_size" {
  description = "Memory size for the shared Forge backend Lambda. 256 MB is the free-tier default on arm64."
  type        = number
  default     = 256
}

variable "lambda_architectures" {
  description = "Lambda instruction set. arm64 (Graviton) is cheaper than x86_64 at the same memory."
  type        = list(string)
  default     = ["arm64"]
}

variable "cognito_user_pool_tier" {
  description = <<-EOT
    Cognito feature plan. ESSENTIALS is required for the free prefix domain
    (managed login / hosted UI) that public PKCE clients and social IdPs use.
    LITE is cheaper after 10k MAU but does not include managed login. At the
    ~1k MAU cost ceiling Essentials is still inside the 10k MAU free allowance.
  EOT
  type        = string
  default     = "ESSENTIALS"

  validation {
    condition     = contains(["LITE", "ESSENTIALS", "PLUS"], var.cognito_user_pool_tier)
    error_message = "cognito_user_pool_tier must be LITE, ESSENTIALS, or PLUS."
  }
}

variable "cognito_domain_prefix" {
  description = "Optional override for the free Cognito prefix domain. Null uses {project}-{env}-{account}."
  type        = string
  default     = null
  nullable    = true
}

variable "cognito_ios_callback_urls" {
  description = "Exact iOS OAuth callback URLs. Default is the Forge custom scheme."
  type        = list(string)
  default     = ["forge://auth/callback"]
}

variable "cognito_ios_logout_urls" {
  description = "Exact iOS OAuth logout URLs. Default matches the Forge custom-scheme callback."
  type        = list(string)
  default     = ["forge://auth/callback"]
}

variable "cognito_web_callback_urls" {
  description = "Web app OAuth callback URLs. Not secrets — set these per environment. Defaults are placeholders so CI can plan."
  type        = list(string)
  default     = ["https://app.example.com/auth/callback"]
}

variable "cognito_web_logout_urls" {
  description = "Web app OAuth logout URLs."
  type        = list(string)
  default     = ["https://app.example.com/auth/logout"]
}

variable "cognito_kotlin_callback_urls" {
  description = "Kotlin / Android OAuth callback URLs. Not secrets — set these per environment."
  type        = list(string)
  default     = ["https://app.example.com/kotlin/auth/callback"]
}

variable "cognito_kotlin_logout_urls" {
  description = "Kotlin / Android OAuth logout URLs."
  type        = list(string)
  default     = ["https://app.example.com/kotlin/auth/logout"]
}

variable "cognito_localhost_callback_urls" {
  description = "Dev-pool-only localhost callback URLs for web and Kotlin clients."
  type        = list(string)
  default = [
    "http://localhost:3000/auth/callback",
    "http://127.0.0.1:3000/auth/callback",
    "http://localhost:8080/auth/callback",
    "http://127.0.0.1:8080/auth/callback",
  ]
}

variable "cognito_localhost_logout_urls" {
  description = "Dev-pool-only localhost logout URLs for web and Kotlin clients."
  type        = list(string)
  default = [
    "http://localhost:3000/auth/logout",
    "http://127.0.0.1:3000/auth/logout",
    "http://localhost:8080/auth/logout",
    "http://127.0.0.1:8080/auth/logout",
  ]
}

variable "devices_catalog_throttling_rate_limit" {
  description = "Steady-state requests per second for the public GET /devices/catalog route."
  type        = number
  default     = 10
}

variable "devices_catalog_throttling_burst_limit" {
  description = "Burst request limit for the public GET /devices/catalog route."
  type        = number
  default     = 20
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
    Create the monthly AWS Budgets COST budget. Default true for the all-AWS
    step-1 stack so an apply cannot forget the $25/mo ceiling. First two AWS
    Budgets are free; notifications need spend_guard_notification_email.
    Dummy-offline still must not apply this module.
  EOT
  type        = bool
  default     = true
}

variable "spend_guard_limit_usd" {
  description = "Monthly USD limit for the spend-guard budget. $25 is the 1k-MAU ceiling for this stack (Bedrock and ElevenLabs stay separate lines)."
  type        = number
  default     = 25
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
