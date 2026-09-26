# Management-event CloudTrail to a locked, encrypted S3 bucket.
# The first copy of management events is free. No data events (those bill).
#
# Gated by create_cloudtrail (default false): there must be exactly one trail
# per AWS account. Enable this on one stack only. Additional trails in the
# same account start billing. The bucket uses its own
# force_destroy_cloudtrail_bucket (default false) so wiping uploads cannot
# take the audit log with it.

resource "aws_s3_bucket" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket        = local.cloudtrail_bucket_name
  force_destroy = var.force_destroy_cloudtrail_bucket

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "expire-management-events"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  count = var.create_cloudtrail ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id_for_naming]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.aws_region}:${local.account_id_for_naming}:trail/${local.name_prefix}-management"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail[0].arn}/AWSLogs/${local.account_id_for_naming}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id_for_naming]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.aws_region}:${local.account_id_for_naming}:trail/${local.name_prefix}-management"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.cloudtrail[0].arn,
      "${aws_s3_bucket.cloudtrail[0].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket[0].json

  depends_on = [
    aws_s3_bucket_public_access_block.cloudtrail,
    aws_s3_bucket_ownership_controls.cloudtrail,
  ]
}

resource "aws_cloudtrail" "management" {
  count = var.create_cloudtrail ? 1 : 0

  name                          = "${local.name_prefix}-management"
  s3_bucket_name                = aws_s3_bucket.cloudtrail[0].id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = local.common_tags
}
