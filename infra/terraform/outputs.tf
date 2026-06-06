output "api_base_url" {
  description = "Base URL shared by the Next.js and Swift clients."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "healthcheck_url" {
  description = "Health endpoint for smoke tests."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/health"
}

output "backend_lambda_name" {
  description = "Name of the shared Forge backend Lambda."
  value       = aws_lambda_function.backend.function_name
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID for shared Forge authentication."
  value       = aws_cognito_user_pool.forge.id
}

output "cognito_web_client_id" {
  description = "Cognito app client ID intended for the Next.js app."
  value       = aws_cognito_user_pool_client.web.id
}

output "cognito_ios_client_id" {
  description = "Cognito app client ID intended for the Swift app."
  value       = aws_cognito_user_pool_client.ios.id
}

output "cognito_identity_pool_id" {
  description = "Cognito identity pool ID for authenticated AWS access from both clients."
  value       = aws_cognito_identity_pool.forge.id
}

output "app_data_table_name" {
  description = "Shared DynamoDB table for profiles, workouts, metrics, and chat data."
  value       = aws_dynamodb_table.app_data.name
}

output "uploads_bucket_name" {
  description = "Bucket used for Forge uploads and generated artifacts."
  value       = aws_s3_bucket.uploads.bucket
}

output "artifacts_bucket_name" {
  description = "Versioned bucket storing Lambda deployment zips for rollback and self-healing."
  value       = aws_s3_bucket.artifacts.bucket
}

output "self_healing_enabled" {
  description = "Whether the EventBridge health probe and healer Lambda are active."
  value       = var.enable_self_healing
}

output "ops_alerts_topic_arn" {
  description = "SNS topic ARN for infrastructure alerts (null when self-healing is disabled)."
  value       = var.enable_self_healing ? aws_sns_topic.ops_alerts[0].arn : null
}

output "ai_provider_secret_arn" {
  description = "Secrets Manager ARN for the AI provider credentials."
  value       = aws_secretsmanager_secret.ai_provider.arn
}

output "terra_secret_arn" {
  description = "Secrets Manager ARN for Terra API credentials and webhook signing secret."
  value       = aws_secretsmanager_secret.terra.arn
}

output "terra_webhook_url" {
  description = "Public Terra webhook destination URL (configure in Terra dashboard)."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/integrations/terra/webhook"
}

output "terra_health_url" {
  description = "Terra integration health endpoint for ops dashboards."
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/integrations/terra/health"
}

output "terra_self_healing_enabled" {
  description = "Whether scheduled Terra self-healing is active."
  value       = var.enable_self_healing && var.enable_terra_self_healing
}

output "client_configuration" {
  description = "Convenient shared config object for wiring both frontends."
  value = {
    apiBaseUrl = aws_apigatewayv2_api.http.api_endpoint
    cognito = {
      region         = var.aws_region
      userPoolId     = aws_cognito_user_pool.forge.id
      webClientId    = aws_cognito_user_pool_client.web.id
      iosClientId    = aws_cognito_user_pool_client.ios.id
      identityPoolId = aws_cognito_identity_pool.forge.id
    }
    storage = {
      uploadsBucket    = aws_s3_bucket.uploads.bucket
      accessLevel      = "private"
      keyPrefixPattern = "private/{identityId}/"
    }
  }
}
