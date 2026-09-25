# PLACEHOLDER — created because backend/infra/prod.tfvars did not exist on main.
# Do not treat these as real production values. No secrets. Only non-secret
# variables already declared in variables.tf. Reused from
# terraform.tfvars.example with environment flipped to "prod".
#
# OWNER: replace allowed_origins and any other prod-specific values before a
# real apply. This file is for CI plan-only:
#   terraform plan -var-file=prod.tfvars

aws_region   = "us-east-1"
project_name = "forge"
environment  = "prod"

allowed_origins = [
  "http://localhost:3000",
]

tags = {
  Owner = "Forge"
}
