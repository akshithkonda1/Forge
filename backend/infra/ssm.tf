# ElevenLabs credentials live in Parameter Store SecureString (standard tier,
# AWS-managed `alias/aws/ssm` key) instead of Secrets Manager (~$0.40/secret/mo).
# Seed after apply — the placeholder value is ignored by the Lambda loader.
# Social IdP secrets are *not* created here; operators put those parameters
# before the first real apply so Terraform can read them (see cognito.tf).

resource "aws_ssm_parameter" "elevenlabs_api_key" {
  name        = local.ssm_elevenlabs_api_key
  description = "ElevenLabs API key for ARIA's designed live mouth. Seed with aws ssm put-parameter --overwrite. Dummy / Device Hub does not need this."
  type        = "SecureString"
  tier        = "Standard"
  value       = "UNSET"
  key_id      = "alias/aws/ssm"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.common_tags
}

resource "aws_ssm_parameter" "elevenlabs_voice_id" {
  name        = local.ssm_elevenlabs_voice_id
  description = "ElevenLabs ARIA voice id. Seed with aws ssm put-parameter --overwrite."
  type        = "SecureString"
  tier        = "Standard"
  value       = "UNSET"
  key_id      = "alias/aws/ssm"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.common_tags
}

resource "aws_ssm_parameter" "elevenlabs_agent_id" {
  name        = local.ssm_elevenlabs_agent_id
  description = "ElevenLabs ARIA conversational-agent id. Seed with aws ssm put-parameter --overwrite."
  type        = "SecureString"
  tier        = "Standard"
  value       = "UNSET"
  key_id      = "alias/aws/ssm"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.common_tags
}
