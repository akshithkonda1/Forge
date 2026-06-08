terraform {
  backend "s3" {
    # Overridden locally via backend.hcl (wire_production.sh) and in CI via Phase 3 workflow.
    bucket         = "forge-terraform-state-placeholder"
    key            = "forge/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "forge-terraform-locks"
    encrypt        = true
  }
}