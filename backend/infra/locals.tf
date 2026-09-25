data "aws_caller_identity" "current" {
  count = var.skip_aws_provider_checks ? 0 : 1
}

data "aws_region" "current" {}

locals {
  name_prefix           = lower(replace("${var.project_name}-${var.environment}", "_", "-"))
  account_id_for_naming = var.skip_aws_provider_checks ? "ci" : data.aws_caller_identity.current[0].account_id

  # Staging rides with production for log retention. Localhost OAuth clients
  # and unsigned dev-override tokens are an explicit allowlist — not "anything
  # that is not prod". beta / testflight / prd / test / ci / development get
  # neither clients nor override tokens. Fail closed.
  is_prod_like = contains(["prod", "production", "staging", "stage"], var.environment)
  is_dev_pool  = contains(["dev", "local", "sandbox"], var.environment)

  # Real apply (skip_aws_provider_checks = false) must not ship placeholder
  # OAuth URLs. CI plan keeps the example.com defaults so it can run without
  # credentials. Variable validation cannot reference other vars on older TF,
  # so clients enforce this with a lifecycle precondition.
  oauth_urls_contain_example_com = anytrue([
    for url in concat(
      var.cognito_web_callback_urls,
      var.cognito_web_logout_urls,
      var.cognito_kotlin_callback_urls,
      var.cognito_kotlin_logout_urls,
    ) : strcontains(url, "example.com")
  ])

  # 30 days in prod-like accounts, 14 in every other pool. An explicit
  # log_retention_days wins when an operator wants something else.
  log_retention_days = coalesce(var.log_retention_days, local.is_prod_like ? 30 : 14)

  generated_uploads_bucket_name = lower(
    replace(
      "${local.name_prefix}-${local.account_id_for_naming}-${data.aws_region.current.region}-uploads",
      "_",
      "-"
    )
  )

  uploads_bucket_name = var.uploads_bucket_name != null ? var.uploads_bucket_name : local.generated_uploads_bucket_name

  cloudtrail_bucket_name = lower(
    replace(
      "${local.name_prefix}-${local.account_id_for_naming}-${data.aws_region.current.region}-cloudtrail",
      "_",
      "-"
    )
  )

  # Cognito prefix domain is free (no custom ACM / CloudFront). Must be
  # globally unique; account id keeps CI and sibling accounts from colliding.
  cognito_domain_prefix = coalesce(
    var.cognito_domain_prefix,
    "${local.name_prefix}-${local.account_id_for_naming}"
  )

  hosted_ui_domain = "${local.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com"

  # Parameter names only. Values are SecureString objects seeded out of band
  # (or created empty by this module for ElevenLabs). Never taken from tfvars.
  ssm_elevenlabs_api_key   = "/${local.name_prefix}/ai/ELEVENLABS_API_KEY"
  ssm_elevenlabs_voice_id  = "/${local.name_prefix}/ai/ELEVENLABS_ARIA_VOICE_ID"
  ssm_elevenlabs_agent_id  = "/${local.name_prefix}/ai/ELEVENLABS_ARIA_AGENT_ID"
  ssm_google_client_id     = "/${local.name_prefix}/cognito/google/client_id"
  ssm_google_client_secret = "/${local.name_prefix}/cognito/google/client_secret"
  ssm_apple_client_id      = "/${local.name_prefix}/cognito/apple/client_id"
  ssm_apple_team_id        = "/${local.name_prefix}/cognito/apple/team_id"
  ssm_apple_key_id         = "/${local.name_prefix}/cognito/apple/key_id"
  ssm_apple_private_key    = "/${local.name_prefix}/cognito/apple/private_key"

  # CI plan has no AWS credentials, so IdP details use non-secret placeholders.
  # A real apply reads SecureString values from Parameter Store.
  google_idp_client_id = (
    var.skip_aws_provider_checks
    ? "ci-placeholder.apps.googleusercontent.com"
    : data.aws_ssm_parameter.cognito_google_client_id[0].value
  )
  google_idp_client_secret = (
    var.skip_aws_provider_checks
    ? "ci-placeholder-google-client-secret"
    : data.aws_ssm_parameter.cognito_google_client_secret[0].value
  )
  apple_idp_client_id = (
    var.skip_aws_provider_checks
    ? "com.forge.ci.placeholder"
    : data.aws_ssm_parameter.cognito_apple_client_id[0].value
  )
  apple_idp_team_id = (
    var.skip_aws_provider_checks
    ? "A1B2C3D4E5"
    : data.aws_ssm_parameter.cognito_apple_team_id[0].value
  )
  apple_idp_key_id = (
    var.skip_aws_provider_checks
    ? "ABCDEFGHIJ"
    : data.aws_ssm_parameter.cognito_apple_key_id[0].value
  )
  apple_idp_private_key = (
    var.skip_aws_provider_checks
    ? "-----BEGIN PRIVATE KEY-----\nCI_PLACEHOLDER\n-----END PRIVATE KEY-----"
    : data.aws_ssm_parameter.cognito_apple_private_key[0].value
  )

  cognito_oauth_scopes = ["email", "openid", "profile"]
  cognito_oauth_idps   = ["COGNITO", "Google", "SignInWithApple"]

  # Every public app client that can mint a JWT this API will accept.
  # Localhost clients exist only on the dev pool.
  cognito_app_client_ids = concat(
    [
      aws_cognito_user_pool_client.web.id,
      aws_cognito_user_pool_client.ios.id,
      aws_cognito_user_pool_client.kotlin.id,
    ],
    aws_cognito_user_pool_client.web_localhost[*].id,
    aws_cognito_user_pool_client.kotlin_localhost[*].id,
  )

  common_tags = merge(
    {
      Application = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "Forge"
    },
    var.tags
  )
}
