data "aws_caller_identity" "current" {
  count = var.skip_aws_provider_checks ? 0 : 1
}

locals {
  account_id = var.skip_aws_provider_checks ? "ci" : data.aws_caller_identity.current[0].account_id
  github_oidc_subs = length(var.github_oidc_allowed_subs) > 0 ? var.github_oidc_allowed_subs : [
    "repo:${var.github_repository}:ref:refs/heads/main",
    "repo:${var.github_repository}:environment:terraform-prod",
  ]
  state_bucket_name = coalesce(
    var.state_bucket_name,
    "forge-tf-state-${local.account_id}"
  )

  # Placeholder ARNs keep the GetObject deny statement valid for CI plan.
  # A real apply uses the caller-supplied deploy role (if any) plus account
  # root. Root is always on the allowlist so this policy cannot lock the
  # account out of its own state — IdP client secrets land in that state
  # after the first apply of the sibling stack.
  deploy_role_arn = (
    var.skip_aws_provider_checks
    ? "arn:aws:iam::ci:role/ci-placeholder-deploy"
    : (
      var.state_bucket_deploy_role_arn != ""
      ? var.state_bucket_deploy_role_arn
      : try(aws_iam_role.github_deploy[0].arn, "")
    )
  )
  deploy_role_name = (
    local.deploy_role_arn == ""
    ? ""
    : element(split("/", local.deploy_role_arn), length(split("/", local.deploy_role_arn)) - 1)
  )
  # Assumed-role sessions present as sts:...:assumed-role/RoleName/session,
  # not as the iam:...:role/RoleName ARN. Allow both so the deploy role can
  # actually GetObject after AssumeRole.
  deploy_role_assumed_arn = (
    local.deploy_role_name == ""
    ? ""
    : "arn:aws:sts::${local.account_id}:assumed-role/${local.deploy_role_name}/*"
  )
  state_get_object_allowed_arns = compact([
    local.deploy_role_arn,
    local.deploy_role_assumed_arn,
    "arn:aws:iam::${local.account_id}:root",
  ])

  common_tags = merge(
    {
      Application = "forge"
      ManagedBy   = "Terraform"
      Purpose     = "terraform-state"
      Repository  = var.github_repository
    },
    var.tags
  )
}

resource "aws_s3_bucket" "tf_state" {
  bucket = local.state_bucket_name

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "alias/aws/s3"
    }
    bucket_key_enabled = true
  }
}

# Versioned so a bad apply can roll state back. Noncurrent versions expire
# after 30 days so the bucket does not grow forever. Stay on SSE-KMS with
# alias/aws/s3 ($0 idle — no customer CMK). Cognito IdP client secrets from
# the sibling stack land in this state file after the first real apply;
# treat the bucket as secret material.
resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.tf_state]
}

data "aws_iam_policy_document" "tf_state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Restrict s3:GetObject to the deploy role (and its assumed-role sessions)
  # plus the account root. Do not lock out root — IdP secrets in state would
  # then be unrecoverable. No DenyUnencryptedObjectUploads: bucket default
  # encryption is SSE-KMS (alias/aws/s3), and requiring the explicit header
  # breaks the Terraform S3 backend which relies on that default.
  statement {
    sid    = "DenyGetObjectExceptDeployAndRoot"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.tf_state.arn}/*"]

    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.state_get_object_allowed_arns
    }
  }

  statement {
    sid    = "DenyCrossAccount"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  policy = data.aws_iam_policy_document.tf_state.json

  depends_on = [
    aws_s3_bucket_public_access_block.tf_state,
    aws_s3_bucket_ownership_controls.tf_state,
  ]
}
