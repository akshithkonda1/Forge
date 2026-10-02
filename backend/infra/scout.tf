# ARIA Scout — the agentic, always-on research computer ARIA calls when a
# turn needs the open web. Off by default (enable_scout = false): nothing
# here is created, planned, or billed until an operator turns it on.
#
# Shape (minimal cost, maximum reach):
#   iPhone ──Cognito JWT──▶ API Gateway  POST /scout/research
#                              │  JWT authorizer (same as every route)
#                              │  injects x-scout-key + x-forge-user (JWT sub)
#                              ▼
#   one small ARM EC2 (t4g.small default): Caddy :443 (Let's Encrypt)
#                              → Scout :8088 → SearXNG (Google/Bing/DDG/Brave/…)
#                              → Grok on Bedrock (instance role, Converse)
#
# Rough monthly cost at on-demand us-east-1 prices: t4g.small ≈ $12,
# 16 GB gp3 ≈ $1.3, public IPv4 ≈ $3.6 → ≈ $17 before Bedrock tokens. The
# default spend guard is $25/month for the whole stack — raise
# spend_guard_limit_usd when you enable Scout, or pick t4g.micro.
#
# Code ships as a zip in the existing uploads bucket (no ECR, no registry
# bill). A new bundle hash replaces the instance (user_data_replace_on_change).
# No SSH: use SSM Session Manager (AmazonSSMManagedInstanceCore).

locals {
  scout_enabled = var.enable_scout
  scout_count   = local.scout_enabled ? 1 : 0
  # Free, no-DNS TLS hostname derived from the Elastic IP unless the operator
  # brings a domain. sslip.io resolves a-b-c-d.sslip.io → a.b.c.d.
  scout_domain = local.scout_enabled ? (
    var.scout_domain != "" ? var.scout_domain : "${replace(aws_eip.scout[0].public_ip, ".", "-")}.sslip.io"
  ) : ""
  scout_ssm_shared_key = "/${local.name_prefix}/scout/SHARED_KEY"
  scout_route_key      = "POST /scout/research"
}

data "archive_file" "scout_bundle" {
  count = local.scout_count

  type        = "zip"
  source_dir  = "${path.module}/.."
  output_path = "${path.module}/build/forge-scout.zip"
  # Scout needs backend/scout, backend/_paths.py and the Lambda package it
  # reuses (SSRF-safe fetch, Bedrock gateway). Everything else stays out.
  excludes = [
    "**/__pycache__", "**/*.pyc", "**/*.pyo", "**/.DS_Store",
    "ai/**", "simrunner/**", "tests/**", "loadtest/**",
    "infra/*.tf", "infra/*.hcl", "infra/*.tfvars", "infra/*.example", "infra/*.md",
    "infra/.terraform/**", "infra/backend/**", "infra/bootstrap/**", "infra/build/**", "infra/scout/**",
    "*.md", "*.toml", "requirements*.txt", "dev_server.py", "organize_users.py",
  ]
}

resource "aws_s3_object" "scout_bundle" {
  count = local.scout_count

  bucket = aws_s3_bucket.uploads.id
  key    = "scout/bundle-${data.archive_file.scout_bundle[0].output_md5}.zip"
  source = data.archive_file.scout_bundle[0].output_path
  etag   = data.archive_file.scout_bundle[0].output_md5

  tags = local.common_tags
}

resource "aws_ssm_parameter" "scout_shared_key" {
  count = local.scout_count

  name        = local.scout_ssm_shared_key
  description = "Shared secret API Gateway injects as x-scout-key; the Scout box refuses every research call without it."
  type        = "SecureString"
  tier        = "Standard"
  value       = var.scout_shared_key
  key_id      = "alias/aws/ssm"

  tags = local.common_tags
}

data "aws_ssm_parameter" "scout_ami" {
  count = local.scout_count
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_vpc" "default" {
  count   = local.scout_count
  default = true
}

data "aws_iam_policy_document" "scout_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scout" {
  count = local.scout_count

  statement {
    sid = "BedrockGrok"

    # Scout's brain is Grok (SCOUT_MODEL_ID, default global.xai.grok-4.7).
    actions = ["bedrock:InvokeModel", "bedrock:Converse"]

    resources = [
      "arn:aws:bedrock:*::foundation-model/xai.*",
      "arn:aws:bedrock:*:*:inference-profile/global.xai.*",
      "arn:aws:bedrock:*:*:inference-profile/us.xai.*",
      "arn:aws:bedrock:*:*:project/default",
    ]
  }

  statement {
    sid       = "ReadOwnBundle"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/scout/*"]
  }

  statement {
    sid       = "ReadSharedKey"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.scout_shared_key[0].arn]
  }
}

resource "aws_iam_role" "scout" {
  count = local.scout_count

  name               = "${local.name_prefix}-scout"
  assume_role_policy = data.aws_iam_policy_document.scout_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scout" {
  count = local.scout_count

  name   = "${local.name_prefix}-scout"
  role   = aws_iam_role.scout[0].id
  policy = data.aws_iam_policy_document.scout[0].json
}

resource "aws_iam_role_policy_attachment" "scout_ssm_core" {
  count = local.scout_count

  role       = aws_iam_role.scout[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "scout" {
  count = local.scout_count

  name = "${local.name_prefix}-scout"
  role = aws_iam_role.scout[0].name

  tags = local.common_tags
}

resource "aws_security_group" "scout" {
  count = local.scout_count

  name        = "${local.name_prefix}-scout"
  description = "ARIA Scout: HTTPS in (API Gateway has no fixed IPs; the shared key gates access), port 80 for ACME only."
  vpc_id      = data.aws_vpc.default[0].id

  ingress {
    description      = "HTTPS from API Gateway"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "ACME HTTP-01 challenge"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Web search, page reads, Bedrock, S3, SSM"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = local.common_tags
}

resource "aws_eip" "scout" {
  count  = local.scout_count
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-scout" })
}

resource "aws_instance" "scout" {
  count = local.scout_count

  ami                    = data.aws_ssm_parameter.scout_ami[0].value
  instance_type          = var.scout_instance_type
  iam_instance_profile   = aws_iam_instance_profile.scout[0].name
  vpc_security_group_ids = [aws_security_group.scout[0].id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scout/user_data.sh.tftpl", {
    aws_region      = var.aws_region
    bundle_uri      = "s3://${aws_s3_bucket.uploads.bucket}/${aws_s3_object.scout_bundle[0].key}"
    shared_key_name = aws_ssm_parameter.scout_shared_key[0].name
    scout_domain    = local.scout_domain
    scout_model_id  = var.scout_model_id
    searxng_image   = var.scout_searxng_image
    compose_version = var.scout_compose_version
    environment     = var.environment
  })
  user_data_replace_on_change = true

  lifecycle {
    precondition {
      condition     = var.skip_aws_provider_checks || length(var.scout_shared_key) >= 32
      error_message = "scout_shared_key must be at least 32 characters when enable_scout is true (e.g. openssl rand -hex 32). Pass it via TF_VAR_scout_shared_key, never a committed tfvars file."
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-scout" })
}

resource "aws_eip_association" "scout" {
  count = local.scout_count

  instance_id   = aws_instance.scout[0].id
  allocation_id = aws_eip.scout[0].id
}

# --- API Gateway: POST /scout/research behind the same Cognito authorizer ---

resource "aws_apigatewayv2_integration" "scout" {
  count = local.scout_count

  api_id               = aws_apigatewayv2_api.http.id
  integration_type     = "HTTP_PROXY"
  integration_method   = "POST"
  integration_uri      = "https://${local.scout_domain}/research"
  timeout_milliseconds = 29000

  request_parameters = {
    "overwrite:header.x-scout-key"  = var.scout_shared_key
    "overwrite:header.x-forge-user" = "$context.authorizer.claims.sub"
  }
}

resource "aws_apigatewayv2_route" "scout" {
  count = local.scout_count

  api_id             = aws_apigatewayv2_api.http.id
  route_key          = local.scout_route_key
  target             = "integrations/${aws_apigatewayv2_integration.scout[0].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
