data "archive_file" "backend_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/app"
  output_path = "${path.module}/build/forge-backend.zip"
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
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
    ]

    resources = [
      aws_dynamodb_table.app_data.arn,
      "${aws_dynamodb_table.app_data.arn}/index/*",
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
    sid = "AISecretRead"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      aws_secretsmanager_secret.ai_provider.arn,
      aws_secretsmanager_secret.terra.arn,
    ]
  }

  statement {
    sid = "TerraSelfHealMetrics"

    actions = [
      "cloudwatch:PutMetricData",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Forge/Terra"]
    }
  }

  statement {
    sid = "BedrockInference"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]

    resources = [
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
    ]
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

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

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

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers  = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  # Hosted UI (OAuth Authorization Code + PKCE) for the web client.
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = var.web_callback_urls
  logout_urls                          = var.web_logout_urls

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_pool_client" "ios" {
  name         = "${local.name_prefix}-ios"
  user_pool_id = aws_cognito_user_pool.forge.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers  = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  # Hosted UI (OAuth Authorization Code + PKCE) for the iOS client.
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = var.ios_callback_urls
  logout_urls                          = var.ios_logout_urls

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_pool_domain" "forge" {
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.forge.id
}

resource "aws_cognito_identity_pool" "forge" {
  identity_pool_name               = "${local.name_prefix}-identity"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.web.id
    provider_name           = aws_cognito_user_pool.forge.endpoint
    server_side_token_check = true
  }

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.ios.id
    provider_name           = aws_cognito_user_pool.forge.endpoint
    server_side_token_check = true
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

  attribute {
    name = "gsi1pk"
    type = "S"
  }

  attribute {
    name = "gsi1sk"
    type = "S"
  }

  global_secondary_index {
    name            = "gsi1"
    hash_key        = "gsi1pk"
    range_key       = "gsi1sk"
    projection_type = "ALL"
  }

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

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
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
}

resource "aws_secretsmanager_secret" "ai_provider" {
  name                    = "${local.name_prefix}/ai/provider"
  description             = "Credentials used by the Forge AI backend."
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret" "terra" {
  name                    = "${local.name_prefix}/integrations/terra"
  description             = "Terra API credentials and webhook signing secret for Forge middleware."
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "backend_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name_prefix}-http-api"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
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

  s3_bucket        = aws_s3_bucket.artifacts.bucket
  s3_key           = aws_s3_object.backend_lambda.key
  source_code_hash = data.archive_file.backend_lambda.output_base64sha256

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  environment {
    variables = {
      AI_PROVIDER_SECRET_ARN                = aws_secretsmanager_secret.ai_provider.arn
      APP_DATA_TABLE_NAME                   = aws_dynamodb_table.app_data.name
      ARIA_BACKEND                          = "bedrock"
      ENVIRONMENT                           = var.environment
      EMIT_TERRA_METRICS                    = tostring(var.enable_terra_self_healing)
      FORGE_API_BASE_URL                    = aws_apigatewayv2_api.http.api_endpoint
      OPS_SELF_HEAL_TOKEN                   = var.ops_self_heal_token
      TERRA_METRIC_NAMESPACE                = "Forge/Terra"
      TERRA_SECRET_ARN                      = aws_secretsmanager_secret.terra.arn
      TERRA_SELF_HEAL_STALE_HOURS           = "24"
      TERRA_SELF_HEAL_SYNCING_STUCK_MINUTES = "90"
      TERRA_WEBHOOK_URL                     = "${aws_apigatewayv2_api.http.api_endpoint}/integrations/terra/webhook"
      UPLOADS_BUCKET_NAME                   = aws_s3_bucket.uploads.bucket
      USER_POOL_ID                          = aws_cognito_user_pool.forge.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.backend_lambda,
    aws_s3_object.backend_lambda,
  ]

  tags = local.common_tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  name             = "${local.name_prefix}-cognito"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [
      aws_cognito_user_pool_client.web.id,
      aws_cognito_user_pool_client.ios.id,
    ]
    issuer = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.forge.id}"
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["authorization", "content-type", "terra-signature", "x-forge-ops-token", "x-amz-date", "x-api-key", "x-amz-security-token"]
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
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
}

resource "aws_apigatewayv2_route" "terra_webhook" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /integrations/terra/webhook"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
}

resource "aws_apigatewayv2_route" "terra_health" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /integrations/terra/health"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
}

resource "aws_apigatewayv2_route" "terra_self_heal" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /integrations/terra/self-heal"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
}

resource "aws_apigatewayv2_route" "terra_self_integrate" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /integrations/terra/self-integrate"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
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
    })
  }

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
