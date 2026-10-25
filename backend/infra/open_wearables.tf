# Open Wearables — AWS-hosted open source (MIT, Momentum). Off by default.
# enable_open_wearables = false: nothing here is created, planned as real
# spend, or billed. This is not on-prem and not a metered SaaS. Terraform
# is the source of truth for the box, the secrets, the webhook route, and
# the instance role.
#
# Shape (docs/open-wearables-integration.md §5, no NAT):
#   wearable vendors ──OAuth / webhooks──▶ one t4g.small (compose)
#       FastAPI + Celery + Postgres 18 + Redis 8 + Caddy :443
#                              │  HMAC POST
#                              ▼
#   API Gateway  POST /integrations/open-wearables/webhook  → Lambda adapter
#
# HealthKit / on-device health data never lands here. Postgres holds vendor
# connections and sync state for the cloud wearables (Oura, WHOOP, Garmin,
# Strava). Forge product rows stay in DynamoDB via the existing ingest
# routes. Official compose applies its own migrations on first boot.

locals {
  open_wearables_enabled = var.enable_open_wearables
  open_wearables_count   = local.open_wearables_enabled ? 1 : 0
  open_wearables_domain = local.open_wearables_enabled ? (
    var.open_wearables_domain != "" ? var.open_wearables_domain : "${replace(aws_eip.open_wearables[0].public_ip, ".", "-")}.sslip.io"
  ) : ""
  open_wearables_route_key = "POST /integrations/open-wearables/webhook"

  open_wearables_secret_keys = [
    "WEBHOOK_SECRET",
    "ADMIN_PASSWORD",
    "POSTGRES_PASSWORD",
    "oura/client_id",
    "oura/client_secret",
    "whoop/client_id",
    "whoop/client_secret",
    "garmin/client_id",
    "garmin/client_secret",
    "strava/client_id",
    "strava/client_secret",
  ]
}

resource "aws_ssm_parameter" "open_wearables" {
  for_each = local.open_wearables_enabled ? toset(local.open_wearables_secret_keys) : toset([])

  name        = "${local.ssm_open_wearables_prefix}/${each.value}"
  description = "Open Wearables secret ${each.value}. Seed with aws ssm put-parameter --overwrite. Never commit the value."
  type        = "SecureString"
  tier        = "Standard"
  value       = "UNSET"
  key_id      = "alias/aws/ssm"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.common_tags
}

data "aws_ssm_parameter" "open_wearables_ami" {
  count = local.open_wearables_count
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_vpc" "open_wearables" {
  count   = local.open_wearables_count
  default = true
}

data "aws_iam_policy_document" "open_wearables_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "open_wearables" {
  count = local.open_wearables_count

  statement {
    sid = "ReadOwnSecrets"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]

    resources = [
      "arn:aws:ssm:${var.aws_region}:${local.account_id_for_naming}:parameter${local.ssm_open_wearables_prefix}",
      "arn:aws:ssm:${var.aws_region}:${local.account_id_for_naming}:parameter${local.ssm_open_wearables_prefix}/*",
    ]
  }

  statement {
    sid = "DecryptOwnSecrets"

    actions = ["kms:Decrypt"]

    resources = [
      "arn:aws:kms:${var.aws_region}:${local.account_id_for_naming}:key/*",
    ]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = ["alias/aws/ssm"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "open_wearables" {
  count = local.open_wearables_count

  name               = "${local.name_prefix}-open-wearables"
  assume_role_policy = data.aws_iam_policy_document.open_wearables_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "open_wearables" {
  count = local.open_wearables_count

  name   = "${local.name_prefix}-open-wearables"
  role   = aws_iam_role.open_wearables[0].id
  policy = data.aws_iam_policy_document.open_wearables[0].json
}

resource "aws_iam_role_policy_attachment" "open_wearables_ssm_core" {
  count = local.open_wearables_count

  role       = aws_iam_role.open_wearables[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "open_wearables" {
  count = local.open_wearables_count

  name = "${local.name_prefix}-open-wearables"
  role = aws_iam_role.open_wearables[0].name

  tags = local.common_tags
}

resource "aws_security_group" "open_wearables" {
  count = local.open_wearables_count

  name        = "${local.name_prefix}-open-wearables"
  description = "Open Wearables: HTTPS for vendor OAuth + webhooks, port 80 for ACME only. Postgres/Redis stay on the compose network."
  vpc_id      = data.aws_vpc.open_wearables[0].id

  ingress {
    description      = "HTTPS for vendor OAuth callbacks and operator API"
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
    description      = "Vendor APIs, Forge webhook, SSM, ECR-public / Docker Hub"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "HTTP for ACME and package indexes (compose pulls are HTTPS)"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = local.common_tags
}

resource "aws_eip" "open_wearables" {
  count  = local.open_wearables_count
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-open-wearables" })
}

resource "aws_instance" "open_wearables" {
  count = local.open_wearables_count

  ami                    = data.aws_ssm_parameter.open_wearables_ami[0].value
  instance_type          = var.open_wearables_instance_type
  iam_instance_profile   = aws_iam_instance_profile.open_wearables[0].name
  vpc_security_group_ids = [aws_security_group.open_wearables[0].id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.open_wearables_volume_gb
    encrypted             = true
    delete_on_termination = false
  }

  user_data = templatefile("${path.module}/open_wearables/user_data.sh.tftpl", {
    aws_region      = var.aws_region
    ssm_prefix      = local.ssm_open_wearables_prefix
    ow_domain       = local.open_wearables_domain
    backend_image   = var.open_wearables_backend_image
    frontend_image  = var.open_wearables_frontend_image
    compose_version = var.open_wearables_compose_version
    environment     = var.environment
    webhook_url     = "${aws_apigatewayv2_api.http.api_endpoint}/integrations/open-wearables/webhook"
  })
  user_data_replace_on_change = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-open-wearables" })
}

resource "aws_eip_association" "open_wearables" {
  count = local.open_wearables_count

  instance_id   = aws_instance.open_wearables[0].id
  allocation_id = aws_eip.open_wearables[0].id
}

resource "aws_apigatewayv2_route" "open_wearables_webhook" {
  count = local.open_wearables_count

  api_id             = aws_apigatewayv2_api.http.id
  route_key          = local.open_wearables_route_key
  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorization_type = "NONE"
}
