data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  generated_uploads_bucket_name = lower(
    replace(
      "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-uploads",
      "_",
      "-"
    )
  )

  uploads_bucket_name = var.uploads_bucket_name != null ? var.uploads_bucket_name : local.generated_uploads_bucket_name

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
