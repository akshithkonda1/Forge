# Partial S3 backend. Bucket and key come from
# backend/<env>.s3.tfbackend (or -backend-config=bucket=...).
# terraform init without those values must fail — never local state.
# Native S3 lock files (use_lockfile) replace DynamoDB locking. Dev and prod
# use different keys so they never share a state file.

terraform {
  backend "s3" {
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
    kms_key_id   = "alias/aws/s3"
  }
}
