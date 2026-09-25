# Prod var set. Not auto-loaded (not terraform.tfvars / *.auto.tfvars).
# Plan: terraform plan -var-file=prod.tfvars
# Dev shares the account and keeps the create_cloudtrail default (false).
environment       = "prod"
create_cloudtrail = true
