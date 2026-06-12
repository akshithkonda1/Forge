data "aws_caller_identity" "current" {
  count = var.skip_aws_provider_checks ? 0 : 1
}

data "aws_region" "current" {}

locals {
  name_prefix           = lower(replace("${var.project_name}-${var.environment}", "_", "-"))
  account_id_for_naming = var.skip_aws_provider_checks ? "ci" : data.aws_caller_identity.current[0].account_id

  generated_uploads_bucket_name = lower(
    replace(
      "${local.name_prefix}-${local.account_id_for_naming}-${data.aws_region.current.name}-uploads",
      "_",
      "-"
    )
  )

  uploads_bucket_name = var.uploads_bucket_name != null ? var.uploads_bucket_name : local.generated_uploads_bucket_name

  cognito_domain_prefix = var.cognito_domain_prefix != null ? var.cognito_domain_prefix : "${local.name_prefix}-${local.account_id_for_naming}"

  cognito_hosted_ui_domain = "https://${local.cognito_domain_prefix}.auth.${data.aws_region.current.name}.amazoncognito.com"

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
