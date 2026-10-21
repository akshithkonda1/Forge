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
    Deployment environment name. This is a security control, not a label.

    Localhost Cognito clients, unsigned dev-override tokens, and seeded demo
    data are allowlisted to environment in {dev, local, sandbox} only. Any
    other name (beta, testflight, prd, test, ci, development, staging, prod)
    is fail-closed: no localhost clients, no localhost IDs on the JWT
    audience, and Terraform sets FORGE_ALLOW_DEV_OVERRIDE=false so the Lambda
    rejects unsigned tokens.

    Deliberately has no default. A value of "dev" inherited by accident is a
    production API that accepts a forged identity, so the choice is made at the
    call site or not at all.
  EOT
  type        = string

  validation {
    # Closed set so a typo like "produciton" cannot be applied. Adding a new
    # name here does not grant localhost clients or override tokens — those
    # require a second add to local.is_dev_pool.
    condition = contains(
      ["local", "dev", "development", "test", "ci", "sandbox", "stage", "staging", "prod", "production"],
      var.environment
    )
    error_message = "environment must be one of: local, dev, development, test, ci, sandbox, stage, staging, prod, production."
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
    Override CloudWatch log retention in days. Null (the default) uses 14 in
    prod-like environments and 7 everywhere else, including the CI plan.
    Keep this in the 7–14 day band unless an operator is debugging a live incident.
  EOT
  type        = number
  default     = null
  nullable    = true
}

variable "lambda_memory_size" {
  description = "Memory size for the shared Forge backend Lambda. 256 MB arm64 is the cheap default (enough for JSON + one sleep image, not a warmer)."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 512
    error_message = "lambda_memory_size must be 128–512 MB. Raise only after profiling; provisioned concurrency is forbidden."
  }
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
  description = "Exact iOS OAuth callback URLs. Default is the Forge custom scheme. Index [0] is iosRedirectUri."
  type        = list(string)
  default     = ["forge://auth/callback"]

  validation {
    condition     = length(var.cognito_ios_callback_urls) > 0
    error_message = "cognito_ios_callback_urls must contain at least one URL."
  }
}

variable "cognito_ios_logout_urls" {
  description = "Exact iOS OAuth logout URLs. Default is the Forge custom-scheme logout. Index [0] is iosLogoutUri."
  type        = list(string)
  default     = ["forge://auth/logout"]

  validation {
    condition     = length(var.cognito_ios_logout_urls) > 0
    error_message = "cognito_ios_logout_urls must contain at least one URL."
  }
}

variable "cognito_web_callback_urls" {
  description = "Web app OAuth callback URLs. Not secrets — set these per environment. Defaults are placeholders so CI can plan; a real apply rejects example.com."
  type        = list(string)
  default     = ["https://app.example.com/auth/callback"]

  validation {
    condition     = length(var.cognito_web_callback_urls) > 0
    error_message = "cognito_web_callback_urls must contain at least one URL."
  }
}

variable "cognito_web_logout_urls" {
  description = "Web app OAuth logout URLs. A real apply rejects example.com."
  type        = list(string)
  default     = ["https://app.example.com/auth/logout"]

  validation {
    condition     = length(var.cognito_web_logout_urls) > 0
    error_message = "cognito_web_logout_urls must contain at least one URL."
  }
}

variable "cognito_kotlin_callback_urls" {
  description = <<-EOT
    Kotlin / Android OAuth callback URLs. Index [0] is the custom scheme
    (kotlinRedirectUri). An https App Link may follow as a second entry only;
    it works only once assetlinks.json is live on that domain.
  EOT
  type        = list(string)
  default     = ["com.forge.app://auth/callback"]

  validation {
    condition     = length(var.cognito_kotlin_callback_urls) > 0
    error_message = "cognito_kotlin_callback_urls must contain at least one URL."
  }
}

variable "cognito_kotlin_logout_urls" {
  description = <<-EOT
    Kotlin / Android OAuth logout URLs. Index [0] is the custom scheme
    (kotlinLogoutUri). An https App Link may follow as a second entry only;
    it works only once assetlinks.json is live on that domain.
  EOT
  type        = list(string)
  default     = ["com.forge.app://auth/logout"]

  validation {
    condition     = length(var.cognito_kotlin_logout_urls) > 0
    error_message = "cognito_kotlin_logout_urls must contain at least one URL."
  }
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
  description = "Steady-state requests per second for the public GET /devices/catalog route. Clients should cache; 2 rps is a scrape ceiling, not a page-load budget."
  type        = number
  default     = 2
}

variable "devices_catalog_throttling_burst_limit" {
  description = "Burst request limit for the public GET /devices/catalog route."
  type        = number
  default     = 10
}

variable "health_throttling_rate_limit" {
  description = "Steady-state requests per second for the public GET /health route."
  type        = number
  default     = 1
}

variable "health_throttling_burst_limit" {
  description = "Burst request limit for the public GET /health route."
  type        = number
  default     = 5
}

variable "lambda_timeout" {
  description = "Timeout, in seconds, for the shared Forge backend Lambda. 15s matches the HTTP API integration and the router overall budget; do not raise it to paper over hung model calls."
  type        = number
  default     = 15

  validation {
    condition     = var.lambda_timeout >= 5 && var.lambda_timeout <= 20
    error_message = "lambda_timeout must be 5–20s. The cheap default is 15s; longer timeouts raise duration cost."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Whether to enable PITR on the shared Forge DynamoDB table."
  type        = bool
  default     = true
}

variable "dynamodb_deletion_protection" {
  description = <<-EOT
    DynamoDB deletion_protection_enabled on aws_dynamodb_table.app_data.
    Default true. Teardown is two applies: set this false, apply, then destroy.
  EOT
  type        = bool
  default     = true
}

variable "cognito_deletion_protection" {
  description = <<-EOT
    Cognito deletion_protection on aws_cognito_user_pool.forge (ACTIVE when
    true, INACTIVE when false). Default true. Teardown is two applies: set
    this false, apply, then destroy.
  EOT
  type        = bool
  default     = true
}

variable "enable_alarms" {
  description = <<-EOT
    Create the ops SNS topic, 7 standard CloudWatch alarms, and the HTTP API
    429 metric filter. Default true (free tier: first 10 standard alarms).
    All alarms use treat_missing_data = notBreaching and notify the one SNS
    topic. Email is attached only when spend_guard_notification_email is set.
  EOT
  type        = bool
  default     = true
}

variable "enable_cost_dashboard" {
  description = <<-EOT
    Create one CloudWatch dashboard (Lambda + HTTP API usage). Default false:
    dashboards are $3/month each and are not needed for the cheap default.
    Email still comes from the existing spend-guard SNS/budget address.
  EOT
  type        = bool
  default     = false
}

variable "lambda_reserved_concurrency" {
  description = <<-EOT
    Reserved concurrent executions for the API Lambda. Null (the default) is
    unreserved — the function shares the account pool. Set a small integer
    cap (≥ 1) and raise it later if you need a ceiling. 0 is rejected: it
    would block every invoke. Pause ARIA with the ARIA_PAUSED SSM parameter
    instead. This is a free cap, not provisioned concurrency (which bills
    and is forbidden by the cheap-guard test).
  EOT
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.lambda_reserved_concurrency == null || var.lambda_reserved_concurrency >= 1
    error_message = "lambda_reserved_concurrency must be null (unreserved) or >= 1. A value of 0 disables all invokes; pause ARIA with the ARIA_PAUSED SSM parameter instead."
  }
}

variable "account_concurrency_limit" {
  description = <<-EOT
    Account-level Lambda concurrent-execution quota used by the 80%
    ConcurrentExecutions alarm. Default 1000 (the usual new-account default).
    Confirm with: aws lambda get-account-settings
    New accounts can be as low as 10 — set this to the real number so the
    alarm is meaningful.
  EOT
  type        = number
  default     = 1000

  validation {
    condition     = var.account_concurrency_limit >= 1
    error_message = "account_concurrency_limit must be >= 1 (aws lambda get-account-settings)."
  }
}

variable "api_throttling_rate_limit" {
  description = "Steady-state requests per second for the HTTP API stage default route. 50 matches the previous hardcoded plan."
  type        = number
  default     = 50
}

variable "api_throttling_burst_limit" {
  description = "Burst request limit for the HTTP API stage default route. 100 matches the previous hardcoded plan."
  type        = number
  default     = 100
}

variable "aria_pause_fail_mode" {
  description = <<-EOT
    What is_aria_paused() returns when SSM GetParameter fails.
    "paused" (default): treat SSM errors as paused. "open": ARIA stays up
    (fail open). Unset ARIA_PAUSED_PARAMETER_NAME always fails open. /health
    and voice stay up either way.
  EOT
  type        = string
  default     = "paused"

  validation {
    condition     = contains(["open", "paused"], var.aria_pause_fail_mode)
    error_message = "aria_pause_fail_mode must be \"open\" or \"paused\"."
  }
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
    Bedrock model id for router slot 1 (Tier 1 Sonnet — default). Empty keeps
    global.anthropic.claude-sonnet-5-5 (ai_router.default_models()). Inert
    while aria_bedrock_enabled is false. US-only residency is
    us.anthropic.claude-sonnet-5-5; In-Region runtime is not supported for
    Claude 5.x on bedrock-runtime. The ladder selects by family, not slot
    order: Sonnet → Grok → Opus → rare ensemble.
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
    Bedrock model id for router slot 2 (Tier 3 Opus). Empty keeps
    global.anthropic.claude-opus-5-5 (ai_router.default_models()). Inert
    while aria_bedrock_enabled is false. US-only residency is
    us.anthropic.claude-opus-5-5. Used for complex planning, not default traffic.
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
    Bedrock model id for router slot 3 (Tier 2 Grok 4.7). Empty keeps the Lambda
    fallback global.xai.grok-4.7 — the Grok 4.7 Global CRIS id on
    bedrock-runtime (US Geo is us.xai.grok-4.7; the same model Scout uses).
    Inert while aria_bedrock_enabled is false. Used when a request is more
    complex than Sonnet should handle alone.
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
    Budgets are free. The budget only ALERTS — it never stops spend. ElevenLabs
    charges are invisible to it (they are not AWS cost); the ElevenLabs cap
    lives in the app quota, not this budget. Dummy-offline still must not
    apply this module.
  EOT
  type        = bool
  default     = true
}

variable "spend_guard_limit_usd" {
  description = "Monthly USD limit for the spend-guard budget. $25 is the 1k-MAU ceiling for this stack (Bedrock is a separate AWS line; ElevenLabs is not visible here)."
  type        = number
  default     = 25
}

variable "spend_guard_notification_email" {
  description = <<-EOT
    Required on a real apply when enable_spend_guard is true (lifecycle
    precondition). Subscribes this address at 80% actual, 100% actual, and
    100% forecasted. Leave empty for Akshith to fill in. CI plan with
    skip_aws_provider_checks may leave this empty.
  EOT
  type        = string
  default     = ""
}

variable "aria_daily_request_cap" {
  description = "Per-user daily Bedrock Converse reservation count. 0 disables the request cap. Inert while aria_bedrock_enabled is false."
  type        = number
  default     = 40

  validation {
    condition     = var.aria_daily_request_cap >= 0
    error_message = "aria_daily_request_cap must be >= 0 (0 disables the cap)."
  }
}

variable "aria_daily_token_cap" {
  description = "Per-user daily reserved max_tokens across Bedrock Converse calls. 0 disables the token cap. Inert while aria_bedrock_enabled is false."
  type        = number
  default     = 20000

  validation {
    condition     = var.aria_daily_token_cap >= 0
    error_message = "aria_daily_token_cap must be >= 0 (0 disables the cap)."
  }
}

variable "create_cloudtrail" {
  description = <<-EOT
    Create the management-event CloudTrail, its locked bucket, and the bucket
    policy. Default false: there must be exactly one trail per AWS account, so
    enable this on one stack only (typically the first / account-level apply).
    Additional trails in the same account start billing.
  EOT
  type        = bool
  default     = false
}

variable "force_destroy_cloudtrail_bucket" {
  description = "Whether Terraform may delete a non-empty CloudTrail bucket. Default false — audit logs should not vanish with the stack."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

# --- ARIA Scout (agentic research computer; scout.tf) ------------------------

variable "enable_scout" {
  description = "Create ARIA Scout: one small ARM EC2 (SearXNG + Scout + Caddy) behind POST /scout/research. Off by default — nothing is created or billed while false."
  type        = bool
  default     = false
}

variable "scout_instance_type" {
  description = "Scout EC2 size. t4g.small (2 GB) fits SearXNG + Scout comfortably; t4g.micro halves the bill but runs tight."
  type        = string
  default     = "t4g.small"
}

variable "scout_shared_key" {
  description = "Secret API Gateway injects as x-scout-key; Scout refuses every call without it. >= 32 chars when enable_scout is true. Supply via TF_VAR_scout_shared_key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "scout_domain" {
  description = "Hostname Caddy serves Scout's TLS certificate for. Empty uses <elastic-ip-with-dashes>.sslip.io (free, no DNS to manage)."
  type        = string
  default     = ""
}

variable "scout_model_id" {
  description = "Bedrock model Scout reasons with. Grok 4.7 Global cross-Region inference profile by default."
  type        = string
  default     = "global.xai.grok-4.7"
}

variable "scout_searxng_image" {
  description = "SearXNG container image. Pin a dated tag or digest for reproducible boots."
  type        = string
  default     = "searxng/searxng:latest"
}

variable "scout_compose_version" {
  description = "Docker Compose v2 release installed on the Scout host."
  type        = string
  default     = "v2.29.7"
}

variable "scout_throttling_burst_limit" {
  description = "API Gateway burst limit for POST /scout/research (Scout also rate-limits per user)."
  type        = number
  default     = 5
}

variable "scout_throttling_rate_limit" {
  description = "API Gateway steady-state requests/second for POST /scout/research."
  type        = number
  default     = 1
}
