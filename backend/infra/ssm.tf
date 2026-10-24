# Secrets for this stack live in Parameter Store SecureString (standard
# tier, AWS-managed `alias/aws/ssm`) instead of Secrets Manager
# (~$0.40/secret/mo). Voice is on-device (Kokoro) — leftover ElevenLabs /
# Fish Audio parameters are not created. Social IdP secrets are *not*
# created here; operators put those parameters before the first real apply
# so Terraform can read them (see cognito.tf). Open Wearables secrets are
# created in open_wearables.tf only when that flag is on.

# ARIA-only kill switch. Standard String (not SecureString) — no KMS. Seeded
# "false"; operators flip it with put-parameter --overwrite. Terraform ignores
# the live value so a pause is not reverted on the next apply.
resource "aws_ssm_parameter" "aria_paused" {
  name        = local.ssm_aria_paused
  description = "ARIA-only kill switch. true pauses chat/router/coach; voice and /health stay up."
  type        = "String"
  tier        = "Standard"
  value       = "false"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.common_tags
}
