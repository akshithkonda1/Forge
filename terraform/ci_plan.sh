#!/usr/bin/env bash
# Ephemeral local backend for terraform plan in CI (no AWS credentials required).
set -euo pipefail

mv backend.tf backend.s3.tf.disabled
cat > backend.tf <<'EOF'
terraform {
  backend "local" {
    path = "ci-plan.tfstate"
  }
}
EOF
terraform init -reconfigure -input=false -lockfile=readonly -no-color
terraform plan -input=false -no-color