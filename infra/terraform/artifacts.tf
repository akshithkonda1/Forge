resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name_prefix}-artifacts"
  force_destroy = var.force_destroy_artifacts_bucket

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-lambda-artifacts"
    status = "Enabled"

    filter {
      prefix = "lambda/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_object" "backend_lambda" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "lambda/forge-backend.zip"
  source = data.archive_file.backend_lambda.output_path
  etag   = filemd5(data.archive_file.backend_lambda.output_path)

  tags = local.common_tags
}