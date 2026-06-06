output "aws_account_id" {
  description = "AWS account ID used for naming and backend configuration."
  value       = data.aws_caller_identity.current.account_id
}

output "terraform_state_bucket" {
  description = "S3 bucket for Forge Terraform remote state."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_lock_table" {
  description = "DynamoDB table for Terraform state locking."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "github_actions_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions production deploys (set as AWS_ROLE_ARN secret)."
  value       = aws_iam_role.github_actions_deploy.arn
}

output "backend_config" {
  description = "Values to copy into infra/terraform/backend.hcl."
  value = {
    bucket         = aws_s3_bucket.terraform_state.bucket
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
    key            = "forge/dev/terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
  }
}