# Partial S3 backend. Bucket and key come from
# backend/<env>.s3.tfbackend (or -backend-config=bucket=...).
# terraform init without those values must fail — never local state.

terraform {
  backend "s3" {
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
