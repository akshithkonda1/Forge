output "api_base_url" {
  description = "Base URL shared by the Next.js, Swift, and Kotlin clients."
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

output "cognito_user_pool_domain" {
  description = "Cognito prefix domain (the free hosted-UI hostname label)."
  value       = aws_cognito_user_pool_domain.forge.domain
}

output "cognito_hosted_ui_domain" {
  description = "Full hosted-UI hostname for generate_client_config and PKCE redirects."
  value       = local.hosted_ui_domain
}

output "cognito_web_client_id" {
  description = "Cognito app client ID intended for the Next.js app."
  value       = aws_cognito_user_pool_client.web.id
}

output "cognito_ios_client_id" {
  description = "Cognito app client ID intended for the Swift app."
  value       = aws_cognito_user_pool_client.ios.id
}

output "cognito_kotlin_client_id" {
  description = "Cognito app client ID intended for the Kotlin app."
  value       = aws_cognito_user_pool_client.kotlin.id
}

output "cognito_web_localhost_client_id" {
  description = "Dev-allowlist-only web localhost client ID. Null unless environment is dev, local, or sandbox."
  value       = try(aws_cognito_user_pool_client.web_localhost[0].id, null)
}

output "cognito_kotlin_localhost_client_id" {
  description = "Dev-allowlist-only Kotlin localhost client ID. Null unless environment is dev, local, or sandbox."
  value       = try(aws_cognito_user_pool_client.kotlin_localhost[0].id, null)
}

output "cognito_identity_pool_id" {
  description = "Cognito identity pool ID for authenticated AWS access from clients."
  value       = aws_cognito_identity_pool.forge.id
}

output "cognito_jwt_audiences" {
  description = "Every app client ID listed on the API Gateway JWT authorizer."
  value       = local.cognito_app_client_ids
}

output "app_data_table_name" {
  description = "Shared DynamoDB table for profiles, workouts, metrics, and chat data."
  value       = aws_dynamodb_table.app_data.name
}

output "uploads_bucket_name" {
  description = "Bucket used for Forge uploads and generated artifacts."
  value       = aws_s3_bucket.uploads.bucket
}

output "cloudtrail_bucket_name" {
  description = "Locked bucket that receives CloudTrail management events. Null unless create_cloudtrail is true."
  value       = var.create_cloudtrail ? aws_s3_bucket.cloudtrail[0].bucket : null
}

output "elevenlabs_parameter_names" {
  description = "Parameter Store names for ELEVENLABS_* SecureString values. Seed out of band."
  value = {
    apiKey  = aws_ssm_parameter.elevenlabs_api_key.name
    voiceId = aws_ssm_parameter.elevenlabs_voice_id.name
    agentId = aws_ssm_parameter.elevenlabs_agent_id.name
  }
}

output "client_configuration" {
  description = "Shared config object for generate_client_config and the other frontends. Localhost client IDs live in dev_client_configuration."
  value = {
    apiBaseUrl = aws_apigatewayv2_api.http.api_endpoint
    cognito = {
      region            = var.aws_region
      userPoolId        = aws_cognito_user_pool.forge.id
      hostedUiDomain    = local.hosted_ui_domain
      webClientId       = aws_cognito_user_pool_client.web.id
      iosClientId       = aws_cognito_user_pool_client.ios.id
      kotlinClientId    = aws_cognito_user_pool_client.kotlin.id
      identityPoolId    = aws_cognito_identity_pool.forge.id
      iosRedirectUri    = var.cognito_ios_callback_urls[0]
      webRedirectUri    = var.cognito_web_callback_urls[0]
      kotlinRedirectUri = var.cognito_kotlin_callback_urls[0]
      iosLogoutUri      = var.cognito_ios_logout_urls[0]
      webLogoutUri      = var.cognito_web_logout_urls[0]
      kotlinLogoutUri   = var.cognito_kotlin_logout_urls[0]
    }
    storage = {
      uploadsBucket    = aws_s3_bucket.uploads.bucket
      accessLevel      = "private"
      keyPrefixPattern = "private/{identityId}/"
    }
  }
}

output "dev_client_configuration" {
  description = "Localhost client IDs. Null unless environment is on the dev allowlist (dev, local, sandbox)."
  value = local.is_dev_pool ? {
    webLocalhostClientId    = aws_cognito_user_pool_client.web_localhost[0].id
    kotlinLocalhostClientId = aws_cognito_user_pool_client.kotlin_localhost[0].id
  } : null
}
