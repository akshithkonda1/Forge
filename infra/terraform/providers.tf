provider "aws" {
  access_key                  = var.skip_aws_provider_checks ? "terraform-ci-placeholder" : null
  region                      = var.aws_region
  secret_key                  = var.skip_aws_provider_checks ? "terraform-ci-placeholder" : null
  skip_credentials_validation = var.skip_aws_provider_checks
  skip_metadata_api_check     = var.skip_aws_provider_checks
  skip_region_validation      = var.skip_aws_provider_checks
  skip_requesting_account_id  = var.skip_aws_provider_checks
  token                       = var.skip_aws_provider_checks ? "terraform-ci-placeholder" : null
}
