output "state_bucket_name" {
  description = "Encrypted S3 bucket for Terraform state. Copy into remote.tf."
  value       = aws_s3_bucket.tf_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket."
  value       = aws_s3_bucket.tf_state.arn
}

output "backend_snippet" {
  description = "S3 backend block to copy into remote.tf after this bootstrap apply."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tf_state.bucket}"
        key          = "backend/terraform.tfstate"
        region       = "${var.aws_region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}
