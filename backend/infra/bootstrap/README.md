# Forge Terraform state bootstrap

Creates the SSE-S3 bucket that holds remote state for `backend/infra`.

This root module stays on **local state**. It is the stack that creates
the bucket (`forge-tf-state-<account-id>` by default), so it cannot store
its own state in that bucket. Do not add a `backend "s3"` block here.

After a deliberate apply, copy `state_bucket_name` into
`../backend/<env>.s3.tfbackend` (replace `ACCOUNT_ID`) and initialize
the sibling stack with:

```bash
cd ..
terraform init -backend-config=backend/<env>.s3.tfbackend
```

CI plans this module with `terraform init -backend=false`.
