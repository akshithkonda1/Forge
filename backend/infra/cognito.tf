# Cognito hosted UI, social IdPs, and the extra public PKCE clients.
#
# Apple / Google client secrets are read from Parameter Store SecureString at
# apply time. They are never taken from tfvars. CI (skip_aws_provider_checks)
# substitutes non-secret placeholders so `terraform plan` stays credential-free.

data "aws_ssm_parameter" "cognito_google_client_id" {
  count           = var.skip_aws_provider_checks ? 0 : 1
  name            = local.ssm_google_client_id
  with_decryption = true
}

data "aws_ssm_parameter" "cognito_google_client_secret" {
  count           = var.skip_aws_provider_checks ? 0 : 1
  name            = local.ssm_google_client_secret
  with_decryption = true
}

data "aws_ssm_parameter" "cognito_apple_client_id" {
  count           = var.skip_aws_provider_checks ? 0 : 1
  name            = local.ssm_apple_client_id
  with_decryption = true
}

data "aws_ssm_parameter" "cognito_apple_team_id" {
  count           = var.skip_aws_provider_checks ? 0 : 1
  name            = local.ssm_apple_team_id
  with_decryption = true
}

data "aws_ssm_parameter" "cognito_apple_key_id" {
  count           = var.skip_aws_provider_checks ? 0 : 1
  name            = local.ssm_apple_key_id
  with_decryption = true
}

data "aws_ssm_parameter" "cognito_apple_private_key" {
  count           = var.skip_aws_provider_checks ? 0 : 1
  name            = local.ssm_apple_private_key
  with_decryption = true
}

resource "aws_cognito_user_pool_domain" "forge" {
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.forge.id
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.forge.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    authorize_scopes = "email profile openid"
    client_id        = local.google_idp_client_id
    client_secret    = local.google_idp_client_secret
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }

  # Cognito rewrites provider_details with OIDC metadata after create, so
  # Terraform must ignore_changes. Rotate the SSM secret with
  # `aws cognito-idp update-identity-provider` (never terraform apply
  # -replace / taint — that recreates the IdP and can unlink existing users).
  lifecycle {
    ignore_changes = [provider_details]
  }
}

resource "aws_cognito_identity_provider" "apple" {
  user_pool_id  = aws_cognito_user_pool.forge.id
  provider_name = "SignInWithApple"
  provider_type = "SignInWithApple"

  provider_details = {
    authorize_scopes = "email name"
    client_id        = local.apple_idp_client_id
    team_id          = local.apple_idp_team_id
    key_id           = local.apple_idp_key_id
    private_key      = local.apple_idp_private_key
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }

  # Same ignore_changes as Google. Rotate via
  # `aws cognito-idp update-identity-provider`, never -replace.
  lifecycle {
    ignore_changes = [provider_details]
  }
}

# Kotlin [0] is the custom scheme (kotlinRedirectUri / kotlinLogoutUri).
# An https App Link may follow as a second entry only; it works only once
# assetlinks.json is live on that domain.
resource "aws_cognito_user_pool_client" "kotlin" {
  name         = "${local.name_prefix}-kotlin"
  user_pool_id = aws_cognito_user_pool.forge.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = local.cognito_oauth_scopes
  supported_identity_providers         = local.cognito_oauth_idps
  callback_urls                        = var.cognito_kotlin_callback_urls
  logout_urls                          = var.cognito_kotlin_logout_urls

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
    # Variable validation cannot reference skip_aws_provider_checks on older TF.
    precondition {
      condition     = var.skip_aws_provider_checks || !local.oauth_urls_contain_example_com
      error_message = "Web or Kotlin callback/logout URLs contain example.com. Set the real per-environment https (or custom-scheme) URLs in tfvars before a real apply. CI plan with skip_aws_provider_checks may keep the placeholders."
    }
  }
}

# Localhost OAuth clients exist only when environment is on the explicit
# allowlist (dev, local, sandbox). Any other name — prod, staging, beta,
# testflight, prd, test, ci — gets no localhost clients and no localhost IDs
# on the JWT authorizer audience. Production clients never list
# http://localhost so a leaked prod client id cannot complete a loopback
# redirect.
resource "aws_cognito_user_pool_client" "web_localhost" {
  count = local.is_dev_pool ? 1 : 0

  name         = "${local.name_prefix}-web-localhost"
  user_pool_id = aws_cognito_user_pool.forge.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = local.cognito_oauth_scopes
  supported_identity_providers         = local.cognito_oauth_idps
  callback_urls                        = var.cognito_localhost_callback_urls
  logout_urls                          = var.cognito_localhost_logout_urls

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

resource "aws_cognito_user_pool_client" "kotlin_localhost" {
  count = local.is_dev_pool ? 1 : 0

  name         = "${local.name_prefix}-kotlin-localhost"
  user_pool_id = aws_cognito_user_pool.forge.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = local.cognito_oauth_scopes
  supported_identity_providers         = local.cognito_oauth_idps
  callback_urls                        = var.cognito_localhost_callback_urls
  logout_urls                          = var.cognito_localhost_logout_urls

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
