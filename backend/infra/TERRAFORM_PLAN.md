# Forge Terraform Plan — "Never Fail, and When It Does, Tell Me Why"

> **Status: planning only. Nothing in this document has been applied.** No
> `terraform apply` was run, no AWS resources were created or changed, and the
> live `.tf` files are unchanged. Everything below is a proposal with concrete,
> copy‑pasteable code you can adopt deliberately.

This plan has two goals, in priority order:

1. **Don't fail.** Remove the structural reasons `terraform apply` fails
   repeatedly, so a normal apply just works.
2. **Diagnose fast.** When a *real* cloud error does happen (throttling, an
   IAM gap, a name collision, wrong account), the stack should tell you the
   cause and the fix in plain English instead of a raw AWS stack trace.

---

## 0. What was actually run (evidence, not guesses)

Terraform 1.9.8 was installed locally and the **exact CI command sequence** was
run against `backend/infra` with `TF_VAR_skip_aws_provider_checks=true`
(read‑only, no AWS credentials):

| Command | Result |
|---|---|
| `terraform init -backend=false -lockfile=readonly` | ✅ success (providers `aws 6.62.0`, `archive 2.8.0`) |
| `terraform fmt -check -recursive` | ✅ clean |
| `terraform validate` | ✅ valid, **3 deprecation warnings** |
| `terraform plan` | ✅ success (planned a full create) |

**Conclusion:** the configuration is *syntactically* healthy and the CI
"Terraform Checks" job is green. The failures you hit are **at real
`apply` time**, which CI has never actually exercised (see
`.github/workflows/terraform.yml` — the apply job was historically gated on a
deleted branch and only runs on push to `main` with AWS secrets present). That
is exactly why "plan is fine but apply fails" keeps happening: **nothing in CI
ever applies, so apply‑time failures are only ever discovered by you, by hand.**

The three deprecation warnings from `terraform validate`:

| Location | Warning |
|---|---|
| `locals.tf:13` | `data.aws_region.current.name` is deprecated → use `.region` |
| `main.tf:265` | `aws_dynamodb_table.hash_key` deprecated → use `key_schema` |
| `main.tf:265` | `aws_dynamodb_table.range_key` deprecated → use `key_schema` |

These are warnings today but become **hard errors** when the AWS provider
crosses to v7.

---

## 1. What is already good (keep it)

The stack is well above scaffold quality. These are strengths worth preserving:

- **Single‑Lambda + `ANY /{proxy+}`** — new backend routes need zero Terraform
  changes. Correct call.
- **Security‑conscious `environment` variable** — no default, closed‑set
  `validation`, and it drives real runtime behavior (dev‑override tokens, demo
  data). This is the right pattern; we extend it, not replace it.
- **Least‑privilege IAM** — Lambda policy is scoped per‑resource; Bedrock is
  scoped to Anthropic model ARNs; the Cognito authenticated role is scoped to
  the caller's own `private/${cognito-identity.amazonaws.com:sub}/` S3 prefix.
- **S3 hardening** — public access block, versioning, SSE, CORS, and
  abort‑incomplete‑multipart lifecycle are all present.
- **DynamoDB** — `PAY_PER_REQUEST`, PITR, SSE, TTL. Sensible.
- **`skip_aws_provider_checks`** — clever toggle that lets CI plan without
  credentials. Keep it.
- **Secret is not in state** — the AI provider secret is created empty and
  seeded out‑of‑band. Correct.

---

## 2. Root‑cause catalog: why `apply` fails

Ordered by how often it produces the "fails every single time" experience.
Each row is a *distinct* failure mode with the AWS error you would see and the
fix.

| # | Root cause | AWS error at apply | Severity | Fix (section) |
|---|---|---|---|---|
| A | **Local state, not shared** (no `remote.tf`) | `EntityAlreadyExists` (IAM), `ResourceInUseException` (DynamoDB), `BucketAlreadyOwnedByYou` (S3), `ResourceExistsException` (Secret), `ResourceAlreadyExistsException` (Log group) | 🔴 Critical | §3.1 |
| B | **Secret 7‑day recovery window** blocks destroy→re‑apply | `InvalidRequestException: You can't create this secret because a secret with this name is already scheduled for deletion` | 🔴 High | §3.2 |
| C | **Log group already exists** (Lambda auto‑creates it) | `ResourceAlreadyExistsException: The specified log group already exists` | 🟠 Medium‑High | §3.3 |
| D | **HTTP API access logging** needs a CloudWatch Logs resource policy in a fresh account | apply error on stage / logs never delivered | 🟠 Medium | §3.4 |
| E | **Floating provider `~> 6.51`** + deprecated attributes | future `apply` breaks on provider bump; deprecation noise now | 🟠 Medium | §3.5 |
| F | **Single‑platform lockfile** (2 hashes) | `terraform init` checksum failure on macOS/other arch | 🟡 Medium | §3.6 |
| G | **Non‑deterministic Lambda zip** (`__pycache__` in `source_dir`) | no hard failure, but spurious function updates every apply | 🟡 Low‑Med | §3.7 |
| H | **`environment` unset** when invoking by hand | `No value for required variable` | 🟡 Low | §3.8 |

### Why **A** is the big one

State is currently a `terraform.tfstate` file on whoever ran `apply` last. The
moment you apply from a second machine, from CI, or after losing/relocating
that file, Terraform's state is empty and it tries to **create resources that
already exist** in the account. Named, account‑unique resources (IAM roles,
DynamoDB table, S3 bucket, Secrets Manager secret, CloudWatch log groups) then
fail with "already exists" and the apply aborts partway — which itself leaves a
half‑built state that makes the *next* apply fail differently. That is the
"fails every single time" loop.

---

## 3. The "never fail" plan (phased, concrete)

### Phase 1 — stop the recurring failures

#### 3.1 Shared remote state + locking (fixes A) — do this first

`remote.tf.example` already exists; it just isn't turned on, and the S3
bucket + lock table it points at don't exist yet. Add a tiny, one‑time
**bootstrap** stack so state has a home before the main stack ever applies.

Proposed `backend/infra/bootstrap/main.tf` (its own local state, applied once):

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.62" } }
}
provider "aws" { region = var.aws_region }
variable "aws_region" { type = string, default = "us-east-1" }

resource "aws_s3_bucket" "tf_state" {
  bucket = "forge-tf-state"                # globally unique; adjust if taken
}
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" } }
}
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_dynamodb_table" "tf_locks" {
  name         = "forge-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute { name = "LockID", type = "S" }
}
```

Then enable the backend by copying `remote.tf.example` → `remote.tf` (already
documented in the README) and `terraform init -migrate-state`.

> **Modern alternative:** Terraform 1.10+ supports **S3‑native state locking**
> (`use_lockfile = true` in the `backend "s3"` block), which removes the need
> for the DynamoDB lock table entirely. Since CI pins Terraform `1.15.0`, this
> is available — recommended to drop `forge-tf-locks` and use `use_lockfile`.

**Adoption for the resources that already exist:** if resources are already in
the account from earlier hand‑applies, don't recreate them — **import** them
into the new remote state (see §6). This is what converts "already exists"
failures into a clean, converged plan.

#### 3.2 Make the secret safe to re‑apply in dev (fixes B)

```hcl
# locals.tf
is_prod = contains(["prod", "production", "staging", "stage"], var.environment)

# main.tf — aws_secretsmanager_secret.ai_provider
recovery_window_in_days = local.is_prod ? 7 : 0   # 0 = delete immediately in dev
```

`0` lets `terraform destroy` fully remove the dev secret so the next `apply`
recreates it cleanly, while prod keeps the 7‑day safety window.

#### 3.3 Own the log group cleanly (fixes C)

Two parts:

1. Keep `aws_cloudwatch_log_group.backend_lambda` (already `depends_on` the
   function) so on a **clean** account the group exists before the function
   runs.
2. When adopting an account where the Lambda already auto‑created
   `/aws/lambda/forge-<env>-api`, **import** the group (see §6) instead of
   letting Terraform try to create it. Add a `check` block (§4) that detects an
   orphaned, unmanaged log group and warns *before* apply.

#### 3.4 Guarantee access‑log delivery (fixes D)

HTTP API access logging can fail or silently drop in a fresh account without a
CloudWatch Logs resource policy. Add one:

```hcl
data "aws_iam_policy_document" "apigw_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api_access.arn}:*"]
    principals { type = "Service", identifiers = ["apigateway.amazonaws.com", "delivery.logs.amazonaws.com"] }
  }
}
resource "aws_cloudwatch_log_resource_policy" "apigw" {
  policy_name     = "${local.name_prefix}-apigw-logs"
  policy_document = data.aws_iam_policy_document.apigw_logs.json
}
```

### Phase 2 — durability & reproducibility

#### 3.5 Pin the provider and clear deprecations (fixes E)

- Tighten `versions.tf` from `~> 6.51` to `~> 6.62` (or pin `= 6.62.0`) so an
  apply months from now uses the provider you tested, not whatever floats in.
- `locals.tf`: `data.aws_region.current.name` → `data.aws_region.current.region`.
- `main.tf` DynamoDB: migrate `hash_key`/`range_key` (table + GSI) to the newer
  `key_schema` form to clear the deprecation. (Same schema, so no table
  replacement — verify with a `plan` showing no destroy.)

#### 3.6 Multi‑platform lockfile (fixes F)

```bash
cd backend/infra
terraform providers lock \
  -platform=linux_amd64 -platform=linux_arm64 \
  -platform=darwin_amd64 -platform=darwin_arm64
```

Commit the updated `.terraform.lock.hcl` so `-lockfile=readonly` works from any
developer laptop and any CI runner arch.

#### 3.7 Deterministic Lambda package (fixes G)

```hcl
data "archive_file" "backend_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/forge-backend.zip"
  excludes    = ["**/__pycache__", "**/*.pyc", "**/*.pyo", "**/.DS_Store"]
}
```

Stops machine‑local bytecode from changing `source_code_hash` and re‑uploading
the function on every apply.

#### 3.8 Friendlier missing‑variable experience (fixes H)

`environment` intentionally has no default (good — it's a security control).
Make the failure obvious rather than cryptic by shipping a checked‑in
`terraform.tfvars` for dev (or documenting `TF_VAR_environment` prominently in
the preflight in §4).

---

## 4. The "tell me why it failed" plan (self‑diagnosing infra)

This is the second half of the request: when a real cloud error happens, the
stack should name the cause and the fix. Four layers, cheapest first.

### 4.1 Input `validation` — reject bad config before any API call

Add actionable `error_message`s to the variables most likely to be wrong:

```hcl
variable "aws_region" {
  # ...
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like 'us-east-1'. Got: ${var.aws_region}."
  }
}

variable "lambda_timeout" {
  # ...
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be 1–900s (AWS Lambda hard limit)."
  }
}

variable "allowed_origins" {
  # ...
  validation {
    condition     = length(var.allowed_origins) > 0
    error_message = "allowed_origins cannot be empty or web/iOS clients get CORS-blocked."
  }
}
```

### 4.2 `precondition` — catch "wrong account / wrong region" before apply

The single most confusing failure is applying to the **wrong AWS account**.
Make it impossible to do silently:

```hcl
variable "allowed_account_ids" {
  description = "Accounts this stack is allowed to deploy into. Empty = any."
  type        = list(string)
  default     = []
}

resource "aws_lambda_function" "backend" {
  # ...
  lifecycle {
    precondition {
      condition = var.skip_aws_provider_checks || length(var.allowed_account_ids) == 0 || contains(var.allowed_account_ids, data.aws_caller_identity.current[0].account_id)
      error_message = "Refusing to apply: current AWS account ${try(data.aws_caller_identity.current[0].account_id, "unknown")} is not in allowed_account_ids. You are pointed at the wrong account — re-check your AWS_PROFILE / credentials."
    }
    precondition {
      condition     = !local.is_prod || alltrue([for o in var.allowed_origins : startswith(o, "https://")])
      error_message = "Production origins must be https://. Found a non-https origin in allowed_origins."
    }
  }
}
```

### 4.3 `check` blocks — continuous assertions that warn, never block

`check` blocks (Terraform 1.5+, available on the pinned 1.15.0) surface
problems as **warnings** so they're visible without aborting an apply:

```hcl
check "secret_is_seeded" {
  data "aws_secretsmanager_secret_version" "ai" {
    secret_id = aws_secretsmanager_secret.ai_provider.id
  }
  assert {
    condition     = can(jsondecode(data.aws_secretsmanager_secret_version.ai.secret_string))
    error_message = "AI provider secret exists but is empty/not-JSON. Seed it: aws secretsmanager put-secret-value --secret-id ${aws_secretsmanager_secret.ai_provider.name} --secret-string '{\"OPENAI_API_KEY\":\"...\"}'"
  }
}

check "health_endpoint" {
  data "http" "health" { url = "${aws_apigatewayv2_api.http.api_endpoint}/health" }
  assert {
    condition     = data.http.health.status_code == 200
    error_message = "Deployed but GET /health did not return 200 — the Lambda or route wiring is broken."
  }
}
```

### 4.4 A preflight "doctor" + an error decoder (the fast‑fix layer)

Two small scripts (checked into `backend/infra/scripts/`) turn opaque AWS
errors into next actions.

**`tf-doctor.sh`** — run before every apply:

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "▶ terraform version"; terraform version | head -1
echo "▶ AWS identity"; aws sts get-caller-identity --query Account --output text \
  || { echo "✗ No/expired AWS credentials. Run aws sso login / set AWS_PROFILE."; exit 1; }
echo "▶ Region: ${AWS_REGION:-us-east-1}"
echo "▶ TF_VAR_environment: ${TF_VAR_environment:?Set TF_VAR_environment (e.g. dev) — it is a required security control}"
echo "▶ State backend reachable"; terraform init -input=false >/dev/null
echo "▶ Speculative plan"; terraform plan -input=false -no-color
```

**`explain-tf-error.sh`** — pipe an apply's stderr through it to get plain
English + the exact remediation:

| AWS error signature | Plain‑English cause | Fix it |
|---|---|---|
| `scheduled for deletion` | Re‑applying a dev secret still in its recovery window | Set `recovery_window_in_days = 0` (dev) or `aws secretsmanager delete-secret --secret-id … --force-delete-without-recovery` |
| `ResourceAlreadyExistsException` (log group) | Lambda auto‑created the log group | `terraform import aws_cloudwatch_log_group.backend_lambda /aws/lambda/forge-<env>-api` |
| `EntityAlreadyExists` (IAM) | State lost / applying without shared state | Enable remote state (§3.1) and `terraform import` the role |
| `ResourceInUseException` (DynamoDB) | Table already exists, not in state | `terraform import aws_dynamodb_table.app_data forge-<env>-app-data` |
| `BucketAlreadyOwnedByYou` | Uploads bucket exists, not in state | `terraform import aws_s3_bucket.uploads <bucket-name>` |
| `ExpiredTokenException` / `InvalidClientTokenId` | Credentials expired | Re‑auth (`aws sso login`) and re‑run |
| `AccessDenied … not authorized to perform: X` | Deploy role missing IAM action `X` | Add `X` to the deploy role policy; the message already names the action |
| `ThrottlingException` / `Rate exceeded` | API throttling on a big apply | Re‑run apply (Terraform retries; it's idempotent) |

The same decoder table can run in the CI apply job so a failed deploy posts the
cause + fix directly into the job summary instead of a raw trace.

### 4.5 Close the CI apply gap

CI currently *never applies*. Recommended (planning): add a **manual
`workflow_dispatch` apply to a dev account** (or a plan‑against‑real‑creds job)
so apply‑time failures are caught in CI with the decoder attached — not
discovered by hand.

---

## 5. Proposed change set (file‑by‑file, planning only)

| File | Change | Fixes |
|---|---|---|
| `bootstrap/` (new) | State bucket + lock table (or S3 `use_lockfile`) | A |
| `remote.tf` (from example) | Turn on S3 backend | A |
| `locals.tf` | `is_prod` local; `aws_region.region`; keep naming | B, E |
| `main.tf` | secret `recovery_window` conditional; archive `excludes`; DynamoDB `key_schema`; log resource policy; preconditions | B, C, D, E, G |
| `variables.tf` | `allowed_account_ids`; validations on region/timeout/origins | diagnosis |
| `versions.tf` | pin provider `~> 6.62` | E |
| `.terraform.lock.hcl` | multi‑platform hashes | F |
| `checks.tf` (new) | `check` blocks for secret + health | diagnosis |
| `scripts/tf-doctor.sh`, `scripts/explain-tf-error.sh` (new) | preflight + decoder | diagnosis |
| `.github/workflows/terraform.yml` | gated dev apply + decoder in summary | diagnosis |

---

## 6. Adoption / rollout (how to land this without a big‑bang failure)

1. **Bootstrap state** (§3.1) in the target account; enable `remote.tf`;
   `terraform init -migrate-state`.
2. **Import** anything that already exists so the first real plan is a converge,
   not a recreate:
   ```bash
   terraform import aws_dynamodb_table.app_data       forge-dev-app-data
   terraform import aws_s3_bucket.uploads             forge-dev-<acct>-us-east-1-uploads
   terraform import aws_secretsmanager_secret.ai_provider forge-dev/ai/provider
   terraform import aws_cloudwatch_log_group.backend_lambda /aws/lambda/forge-dev-api
   terraform import aws_iam_role.backend_lambda       forge-dev-backend-lambda
   # …repeat for other named resources a plan reports as "to create" but that exist
   ```
3. Apply the Phase‑1 changes (§3.2–3.4) and confirm a **no‑op / minimal** plan.
4. Layer in Phase‑2 (§3.5–3.7) and the diagnosis layer (§4).
5. Wire the CI apply gate (§4.5).

---

## 7. Explicitly out of scope

- No `terraform apply` and no live AWS changes were performed by this plan.
- No new AWS account, no Bedrock enablement changes (kill‑switch stays as‑is:
  `aria_bedrock_enabled = false`).
- No secret values committed to state or repo.

---

## 8. Appendix — reproduce the evidence

```bash
cd backend/infra
export AWS_EC2_METADATA_DISABLED=true TF_VAR_environment=dev TF_VAR_skip_aws_provider_checks=true
terraform init -backend=false -input=false -lockfile=readonly -no-color
terraform fmt -check -diff -recursive -no-color
terraform validate -no-color        # 3 deprecation warnings, 0 errors
terraform plan -input=false -no-color
```
