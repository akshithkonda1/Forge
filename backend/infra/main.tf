data "archive_file" "backend_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/forge-backend.zip"
  # Keep the zip hash stable across developer machines / CI. Bytecode and OS
  # junk in source_dir would otherwise rewrite source_code_hash and upload the
  # function on every apply (TERRAFORM_PLAN.md §3.7).
  excludes = ["**/__pycache__", "**/*.pyc", "**/*.pyo", "**/.DS_Store"]
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "authenticated_identity_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.forge.id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

data "aws_iam_policy_document" "backend_lambda" {
  statement {
    sid = "CloudWatchLogs"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "${aws_cloudwatch_log_group.backend_lambda.arn}:*",
    ]
  }

  statement {
    sid = "AppDataTableAccess"

    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
    ]

    resources = [
      aws_dynamodb_table.app_data.arn,
    ]
  }

  statement {
    sid = "UploadsBucketAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "${aws_s3_bucket.uploads.arn}/*",
    ]
  }

  statement {
    sid = "UploadsBucketList"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.uploads.arn,
    ]
  }

  statement {
    sid = "AriaPauseRead"

    actions = [
      "ssm:GetParameter",
    ]

    resources = [
      aws_ssm_parameter.aria_paused.arn,
    ]
  }

  dynamic "statement" {
    for_each = local.open_wearables_enabled ? [1] : []

    content {
      sid = "OpenWearablesWebhookSecret"

      actions = [
        "ssm:GetParameter",
      ]

      resources = [
        aws_ssm_parameter.open_wearables["WEBHOOK_SECRET"].arn,
      ]
    }
  }

  dynamic "statement" {
    for_each = local.open_wearables_enabled ? [1] : []

    content {
      sid = "OpenWearablesWebhookDecrypt"

      actions = [
        "kms:Decrypt",
      ]

      resources = [
        "arn:aws:kms:${var.aws_region}:${local.account_id_for_naming}:key/*",
      ]

      condition {
        test     = "ForAnyValue:StringEquals"
        variable = "kms:ResourceAliases"
        values   = ["alias/aws/ssm"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ssm.${var.aws_region}.amazonaws.com"]
      }
    }
  }

  statement {
    sid = "BedrockInvokeClaudeAndGrok"

    # Lets the AI router, coach routes, and ARIA's live reasoning path call
    # the configured Claude and Grok ids via Converse *if* ARIA_BEDROCK_ENABLED
    # is true. Default is false — unused on Dummy-offline and
    # live-API-no-Bedrock (no token spend while the flag stays off).
    #
    # Resources are the specific foundation-model and us.*/global.* inference
    # profile ARNs for the three router slots (and Scout when enabled). The
    # sibling geo profile is included so Bedrock can route internationally.
    # No anthropic.* / xai.* wildcards. Still gated by the flag, account
    # model-access, and (for Anthropic) Marketplace subscribe / FTU.
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]

    resources = concat(
      local.bedrock_foundation_model_arns,
      local.bedrock_inference_profile_arns,
    )
  }
}

data "aws_iam_policy_document" "authenticated_identity_s3_access" {
  statement {
    sid = "ListOwnPrefix"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.uploads.arn,
    ]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "private/$${cognito-identity.amazonaws.com:sub}",
        "private/$${cognito-identity.amazonaws.com:sub}/*",
      ]
    }
  }

  statement {
    sid = "ManageOwnObjects"

    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.uploads.arn}/private/$${cognito-identity.amazonaws.com:sub}/*",
    ]
  }
}

resource "aws_cognito_user_pool" "forge" {
  name = "${local.name_prefix}-users"

  # ESSENTIALS: free prefix domain + managed login for the authorization-code
  # + PKCE flow and Apple/Google IdPs. LITE is cheaper after 10k MAU but does
  # not include managed login. At ~1k MAU Essentials is still $0 (10k free).
  user_pool_tier = var.cognito_user_pool_tier

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  # ACTIVE blocks terraform destroy / DeleteUserPool. Teardown is two applies:
  # set cognito_deletion_protection=false, apply, then destroy.
  deletion_protection = var.cognito_deletion_protection ? "ACTIVE" : "INACTIVE"

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name_prefix}-web"
  user_pool_id = aws_cognito_user_pool.forge.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = local.cognito_oauth_scopes
  supported_identity_providers         = local.cognito_oauth_idps
  callback_urls                        = var.cognito_web_callback_urls
  logout_urls                          = var.cognito_web_logout_urls

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  depends_on = [
    aws_cognito_identity_provider.google,
    aws_cognito_identity_provider.apple,
  ]

  lifecycle {
    precondition {
      condition     = var.skip_aws_provider_checks || !local.oauth_urls_contain_example_com
      error_message = "Web or Kotlin callback/logout URLs contain example.com. Set the real per-environment https (or custom-scheme) URLs in tfvars before a real apply. CI plan with skip_aws_provider_checks may keep the placeholders."
    }
  }
}

resource "aws_cognito_user_pool_client" "ios" {
  name         = "${local.name_prefix}-ios"
  user_pool_id = aws_cognito_user_pool.forge.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = local.cognito_oauth_scopes
  supported_identity_providers         = local.cognito_oauth_idps
  callback_urls                        = var.cognito_ios_callback_urls
  logout_urls                          = var.cognito_ios_logout_urls

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  depends_on = [
    aws_cognito_identity_provider.google,
    aws_cognito_identity_provider.apple,
  ]
}

resource "aws_cognito_identity_pool" "forge" {
  identity_pool_name               = "${local.name_prefix}-identity"
  allow_unauthenticated_identities = false

  dynamic "cognito_identity_providers" {
    for_each = local.cognito_app_client_ids

    content {
      client_id               = cognito_identity_providers.value
      provider_name           = aws_cognito_user_pool.forge.endpoint
      server_side_token_check = true
    }
  }
}

resource "aws_dynamodb_table" "app_data" {
  name         = "${local.name_prefix}-app-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # No GSI: the Lambda storage layer only reads/writes pk/sk. An ALL-projection
  # GSI previously doubled write cost with zero query benefit. Re-add when an
  # access pattern (metrics-by-type, activity feed) actually writes gsi1pk/sk.

  # Blocks terraform destroy / DeleteTable. Teardown is two applies: set
  # dynamodb_deletion_protection=false, apply, then destroy.
  deletion_protection_enabled = var.dynamodb_deletion_protection

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = local.common_tags
}

resource "aws_s3_bucket" "uploads" {
  bucket        = local.uploads_bucket_name
  force_destroy = var.force_destroy_uploads_bucket

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "uploads" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.uploads.arn,
      "${aws_s3_bucket.uploads.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  policy = data.aws_iam_policy_document.uploads.json

  depends_on = [
    aws_s3_bucket_public_access_block.uploads,
    aws_s3_bucket_ownership_controls.uploads,
  ]
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "uploads" {
  description             = "SSE-KMS for cycle-report ciphertext. Template only — this PR does not apply."
  deletion_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["DELETE", "GET", "HEAD", "POST", "PUT"]
    allowed_origins = var.allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-cycle-reports"
    status = "Enabled"

    filter {
      prefix = "cycle-reports/"
    }

    expiration {
      days = 1
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_cloudwatch_log_group" "backend_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = local.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name_prefix}-http-api"
  retention_in_days = local.log_retention_days

  tags = local.common_tags
}

data "aws_iam_policy_document" "api_access_logs" {
  statement {
    sid    = "AllowAPIGatewayAccessLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "${aws_cloudwatch_log_group.api_access.arn}:*",
    ]
  }
}

resource "aws_cloudwatch_log_resource_policy" "api_access" {
  policy_name     = "${local.name_prefix}-apigw-access-logs"
  policy_document = data.aws_iam_policy_document.api_access_logs.json
}

resource "aws_iam_role" "backend_lambda" {
  name               = "${local.name_prefix}-backend-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "backend_lambda" {
  name   = "${local.name_prefix}-backend-lambda"
  role   = aws_iam_role.backend_lambda.id
  policy = data.aws_iam_policy_document.backend_lambda.json
}

resource "aws_iam_role" "authenticated_identity" {
  name               = "${local.name_prefix}-identity-authenticated"
  assume_role_policy = data.aws_iam_policy_document.authenticated_identity_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "authenticated_identity_s3_access" {
  name   = "${local.name_prefix}-identity-s3-access"
  role   = aws_iam_role.authenticated_identity.id
  policy = data.aws_iam_policy_document.authenticated_identity_s3_access.json
}

resource "aws_cognito_identity_pool_roles_attachment" "forge" {
  identity_pool_id = aws_cognito_identity_pool.forge.id

  roles = {
    authenticated = aws_iam_role.authenticated_identity.arn
  }
}

resource "aws_lambda_function" "backend" {
  function_name = "${local.name_prefix}-api"
  role          = aws_iam_role.backend_lambda.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  architectures = var.lambda_architectures

  filename         = data.archive_file.backend_lambda.output_path
  source_code_hash = data.archive_file.backend_lambda.output_base64sha256

  memory_size                    = var.lambda_memory_size
  timeout                        = var.lambda_timeout
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      ARIA_PAUSED_PARAMETER_NAME = aws_ssm_parameter.aria_paused.name
      ARIA_PAUSE_FAIL_MODE       = var.aria_pause_fail_mode
      ARIA_DAILY_REQUEST_CAP     = tostring(var.aria_daily_request_cap)
      ARIA_DAILY_TOKEN_CAP       = tostring(var.aria_daily_token_cap)
      APP_DATA_TABLE_NAME        = aws_dynamodb_table.app_data.name
      ARIA_BEDROCK_ENABLED       = var.aria_bedrock_enabled ? "true" : "false"
      ENVIRONMENT                = var.environment
      # Fail-closed twin of local.is_dev_pool. Only dev/local/sandbox get
      # unsigned override tokens and seeded demo data.
      FORGE_ALLOW_DEV_OVERRIDE = local.is_dev_pool ? "true" : "false"
      # Router slots. Passing "" would override ai_router.py's default with an
      # empty model id, so an unset variable falls back to the code default.
      # Inert while ARIA_BEDROCK_ENABLED is false. Slot 1/2 ids match
      # ai_router.default_models() (Claude Sonnet 5.5 / Opus 5.5 Global CRIS);
      # slot 3 is Grok 4.7 Global CRIS. IAM also allows the sibling us.*
      # profile so Bedrock can route internationally.
      AI_ROUTER_MODEL_1_ID   = var.ai_router_model_1_id != "" ? var.ai_router_model_1_id : "global.anthropic.claude-sonnet-5-5"
      AI_ROUTER_MODEL_1_NAME = var.ai_router_model_1_name != "" ? var.ai_router_model_1_name : "Claude Sonnet 5.5"
      AI_ROUTER_MODEL_2_ID   = var.ai_router_model_2_id != "" ? var.ai_router_model_2_id : "global.anthropic.claude-opus-5-5"
      AI_ROUTER_MODEL_2_NAME = var.ai_router_model_2_name != "" ? var.ai_router_model_2_name : "Claude Opus 5.5"
      AI_ROUTER_MODEL_3_ID   = var.ai_router_model_3_id != "" ? var.ai_router_model_3_id : "global.xai.grok-4.7"
      AI_ROUTER_MODEL_3_NAME = var.ai_router_model_3_name != "" ? var.ai_router_model_3_name : "Grok"
      UPLOADS_BUCKET_NAME    = aws_s3_bucket.uploads.bucket
      UPLOADS_KMS_KEY_ARN    = aws_kms_key.uploads.arn
      USER_POOL_ID           = aws_cognito_user_pool.forge.id
      OPEN_WEARABLES_WEBHOOK_PARAMETER_NAME = (
        local.open_wearables_enabled ? aws_ssm_parameter.open_wearables["WEBHOOK_SECRET"].name : ""
      )
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.backend_lambda,
  ]

  tags = local.common_tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  name             = "${local.name_prefix}-cognito"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = local.cognito_app_client_ids
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.forge.id}"
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["authorization", "content-type", "x-amz-date", "x-api-key", "x-amz-security-token"]
    allow_methods     = ["DELETE", "GET", "OPTIONS", "PATCH", "POST", "PUT"]
    allow_origins     = var.allowed_origins
    expose_headers    = ["content-type"]
    max_age           = 86400
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "backend" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.backend.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 15000
}

resource "aws_apigatewayv2_route" "root" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /"
  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "health" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorization_type = "NONE"
}

# Public product shelf only. POST /devices/catalog/seen stays on the JWT
# {proxy+} route. More-specific static routes win over ANY /{proxy+}.
# Clients should cache this catalog — the per-route throttle is a scrape
# ceiling (2 rps / burst 10), not a page-load budget.
resource "aws_apigatewayv2_route" "devices_catalog" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /devices/catalog"
  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId         = "$context.requestId"
      sourceIp          = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      protocol          = "$context.protocol"
      httpMethod        = "$context.httpMethod"
      routeKey          = "$context.routeKey"
      status            = "$context.status"
      responseLength    = "$context.responseLength"
      integrationError  = "$context.integration.error"
      integrationStatus = "$context.integration.integrationStatus"
      authorizerError   = "$context.authorizer.error"
      authorizerStatus  = "$context.authorizer.status"
    })
  }

  default_route_settings {
    throttling_burst_limit = var.api_throttling_burst_limit
    throttling_rate_limit  = var.api_throttling_rate_limit
  }

  route_settings {
    route_key              = aws_apigatewayv2_route.devices_catalog.route_key
    throttling_burst_limit = var.devices_catalog_throttling_burst_limit
    throttling_rate_limit  = var.devices_catalog_throttling_rate_limit
  }

  route_settings {
    route_key              = aws_apigatewayv2_route.health.route_key
    throttling_burst_limit = var.health_throttling_burst_limit
    throttling_rate_limit  = var.health_throttling_rate_limit
  }

  # ARIA Scout research route (scout.tf) — only when enable_scout is true.
  dynamic "route_settings" {
    for_each = local.scout_enabled ? [local.scout_route_key] : []

    content {
      route_key              = route_settings.value
      throttling_burst_limit = var.scout_throttling_burst_limit
      throttling_rate_limit  = var.scout_throttling_rate_limit
    }
  }

  # Open Wearables webhook (open_wearables.tf) — HMAC, not JWT.
  dynamic "route_settings" {
    for_each = local.open_wearables_enabled ? [local.open_wearables_route_key] : []

    content {
      route_key              = route_settings.value
      throttling_burst_limit = var.open_wearables_throttling_burst_limit
      throttling_rate_limit  = var.open_wearables_throttling_rate_limit
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.api_access]

  tags = local.common_tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# Monthly COST budget. Default on for step 1 so an apply cannot forget the
# $25/mo ceiling. First two AWS Budgets are free. Claude Marketplace token
# charges may appear under the model provider, not "Amazon Bedrock", so this
# is an account-level COST budget rather than a Bedrock-only filter.
#
# Email alerts fire at 80/100 actual and 100 forecasted. At 100% actual the
# budget action below attaches a Deny-Bedrock IAM policy to the API Lambda
# (and Scout / Open Wearables instance roles when those flags are on).
resource "aws_budgets_budget" "spend_guard" {
  count = var.enable_spend_guard ? 1 : 0

  name         = "${local.name_prefix}-monthly-spend-guard"
  budget_type  = "COST"
  limit_amount = tostring(var.spend_guard_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.spend_guard_notification_email != "" ? [
      { threshold = 80, type = "ACTUAL" },
      { threshold = 100, type = "ACTUAL" },
      { threshold = 100, type = "FORECASTED" },
    ] : []

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = [var.spend_guard_notification_email]
    }
  }

  lifecycle {
    precondition {
      condition     = var.skip_aws_provider_checks || var.spend_guard_notification_email != ""
      error_message = "spend_guard_notification_email must be non-empty on a real apply when enable_spend_guard is true. Alerts fire at 80/100; a budget action denies Bedrock at 100% actual."
    }
  }

  tags = local.common_tags
}

data "aws_iam_policy_document" "deny_bedrock" {
  statement {
    sid    = "DenyBedrockAtBudgetCap"
    effect = "Deny"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "deny_bedrock" {
  count = var.enable_spend_guard ? 1 : 0

  name        = "${local.name_prefix}-deny-bedrock"
  description = "Attached by the spend-guard budget action at 100% actual. Blocks live Bedrock invokes."
  policy      = data.aws_iam_policy_document.deny_bedrock.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "budgets_action_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "budgets_action_exec" {
  count = var.enable_spend_guard ? 1 : 0

  statement {
    sid = "AttachDenyBedrock"

    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]

    resources = concat(
      [aws_iam_role.backend_lambda.arn],
      aws_iam_role.scout[*].arn,
      aws_iam_role.open_wearables[*].arn,
    )
  }

  statement {
    sid = "ReadDenyBedrockPolicy"

    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
    ]

    resources = [aws_iam_policy.deny_bedrock[0].arn]
  }
}

resource "aws_iam_role" "budgets_action" {
  count = var.enable_spend_guard ? 1 : 0

  name               = "${local.name_prefix}-budgets-action"
  assume_role_policy = data.aws_iam_policy_document.budgets_action_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "budgets_action" {
  count = var.enable_spend_guard ? 1 : 0

  name   = "${local.name_prefix}-budgets-action"
  role   = aws_iam_role.budgets_action[0].id
  policy = data.aws_iam_policy_document.budgets_action_exec[0].json
}

resource "aws_budgets_budget_action" "deny_bedrock" {
  count = var.enable_spend_guard ? 1 : 0

  budget_name        = aws_budgets_budget.spend_guard[0].name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action[0].arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.deny_bedrock[0].arn
      roles = compact(concat(
        [aws_iam_role.backend_lambda.name],
        aws_iam_role.scout[*].name,
        aws_iam_role.open_wearables[*].name,
      ))
    }
  }

  subscriber {
    address           = var.spend_guard_notification_email != "" ? var.spend_guard_notification_email : "ci-placeholder@example.com"
    subscription_type = "EMAIL"
  }

  lifecycle {
    precondition {
      condition     = var.skip_aws_provider_checks || var.spend_guard_notification_email != ""
      error_message = "spend_guard_notification_email must be non-empty on a real apply; it is the budget-action subscriber."
    }
  }
}
