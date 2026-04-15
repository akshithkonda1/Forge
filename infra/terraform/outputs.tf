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

output "app_data_table_name" {
  description = "Shared DynamoDB table for profiles, workouts, metrics, and chat data."
  value       = aws_dynamodb_table.app_data.name
}

output "uploads_bucket_name" {
  description = "Bucket used for Forge uploads and generated artifacts."
  value       = aws_s3_bucket.uploads.bucket
}

output "ai_provider_secret_arn" {
  description = "Secrets Manager ARN for the AI provider credentials."
  value       = aws_secretsmanager_secret.ai_provider.arn
}

output "client_configuration" {
  description = "Convenient shared config object for wiring both frontends."
  value = {
    apiBaseUrl = aws_apigatewayv2_api.http.api_endpoint
    cognito = {
      region      = var.aws_region
      userPoolId  = aws_cognito_user_pool.forge.id
      webClientId = aws_cognito_user_pool_client.web.id
      iosClientId = aws_cognito_user_pool_client.ios.id
    }
    storage = {
      uploadsBucket = aws_s3_bucket.uploads.bucket
    }
  }
}
