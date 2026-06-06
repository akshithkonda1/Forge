resource "aws_cloudwatch_event_rule" "terra_self_heal_schedule" {
  count               = var.enable_self_healing && var.enable_terra_self_healing ? 1 : 0
  name                = "${local.name_prefix}-terra-self-heal"
  description         = "Periodic Terra integration health assessment and stale-connection repair."
  schedule_expression = "rate(${var.terra_self_heal_interval_minutes} minutes)"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "terra_self_heal_backend" {
  count     = var.enable_self_healing && var.enable_terra_self_healing ? 1 : 0
  rule      = aws_cloudwatch_event_rule.terra_self_heal_schedule[0].name
  target_id = "forge-backend-terra-heal"
  arn       = aws_lambda_function.backend.arn

  input = jsonencode({
    forgeAction = "terra-self-heal"
  })
}

resource "aws_lambda_permission" "eventbridge_terra_self_heal" {
  count         = var.enable_self_healing && var.enable_terra_self_healing ? 1 : 0
  statement_id  = "AllowEventBridgeTerraSelfHeal"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.terra_self_heal_schedule[0].arn
}

resource "aws_cloudwatch_metric_alarm" "terra_integration_health" {
  count               = var.enable_self_healing && var.enable_terra_self_healing ? 1 : 0
  alarm_name          = "${local.name_prefix}-terra-integration-health"
  alarm_description   = "Terra middleware integration health dropped below threshold."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "IntegrationHealth"
  namespace           = "Forge/Terra"
  period              = max(var.terra_self_heal_interval_minutes * 60, 300)
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.ops_alerts[0].arn]
  ok_actions    = [aws_sns_topic.ops_alerts[0].arn]

  tags = local.common_tags
}