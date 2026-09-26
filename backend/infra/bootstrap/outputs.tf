output "state_bucket_name" {
  description = "Encrypted S3 bucket for Terraform state. Substitute for ACCOUNT_ID in backend/*.s3.tfbackend."
  value       = aws_s3_bucket.tf_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket."
  value       = aws_s3_bucket.tf_state.arn
}

output "backend_snippet" {
  description = "Fill bucket in backend/infra/backend/<env>.s3.tfbackend after this apply. Dev and prod use different keys."
  value       = <<-EOT
    # terraform init -backend-config=backend/<env>.s3.tfbackend
    bucket = "${aws_s3_bucket.tf_state.bucket}"
    # key = "backend/dev/terraform.tfstate"  or  "backend/prod/terraform.tfstate"
  EOT
}
