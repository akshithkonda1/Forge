# Information management. Terraform is the source of truth for where data
# lives. HealthKit / on-device health data is not a store in this stack and
# must not be added. Wearable *vendor* sync (Open Wearables) is AWS-hosted
# open source, off until enable_open_wearables is true.

locals {
  information_stores = {
    forge_product = {
      system     = "DynamoDB aws_dynamodb_table.app_data"
      encryption = "AWS-owned key (server_side_encryption.enabled)"
      transport  = "AWS API TLS (DynamoDB HTTPS). No public table endpoint."
      retention  = "TTL attribute on rows that set it; PITR ${var.enable_point_in_time_recovery}"
      migrations = "Single-table pk/sk. No SQL migrations. Schema evolves in Lambda storage/keys.py."
      healthkit  = "never stored. Phone-side HealthKit stays on the device."
    }
    open_wearables = {
      system     = local.open_wearables_enabled ? "Postgres 18 + Redis 8 on aws_instance.open_wearables (compose)" : "not created (enable_open_wearables = false)"
      encryption = "Encrypted gp3 root volume. Secrets in SSM SecureString."
      transport  = "Postgres and Redis bound to the compose network only. No 5432/6379 ingress."
      retention  = "Volume delete_on_termination = false. Operator snapshots via SSM / AWS Backup if needed."
      migrations = "Official image entrypoint (Alembic or equivalent) on first boot. Terraform does not run SQL."
      healthkit  = "never stored. Cloud vendor connections (Oura/WHOOP/Garmin/Strava) only."
    }
    uploads = {
      system     = "S3 aws_s3_bucket.uploads"
      encryption = "SSE-KMS alias/aws/s3"
      transport  = "TLS-only bucket policy"
      retention  = "cycle-reports/ expire in 1 day; incomplete MPU abort"
    }
    audit = {
      system     = var.create_cloudtrail ? "CloudTrail management events → locked S3 bucket" : "not created (create_cloudtrail = false; prod.tfvars turns it on)"
      encryption = "SSE-KMS alias/aws/s3"
      transport  = "TLS-only bucket policy"
    }
    terraform_state = {
      system     = "bootstrap S3 bucket (separate root module)"
      encryption = "SSE-KMS alias/aws/s3"
      locking    = "native S3 use_lockfile; dev and prod keys are different"
    }
  }
}

output "information_stores" {
  description = "Where Forge data lives, how it is encrypted, and how it migrates. HealthKit is not a store."
  value       = local.information_stores
}
