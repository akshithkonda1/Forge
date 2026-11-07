# Free-tier CloudWatch alarms (standard resolution) plus one SNS topic.
# First 10 standard alarms are free. This module creates 8, all optional
# behind var.enable_alarms. Missing datapoints never fire
# (treat_missing_data = notBreaching). Email is attached only when
# spend_guard_notification_email is non-empty (the same address the budget uses).

resource "aws_sns_topic" "ops_alarms" {
  count = var.enable_alarms ? 1 : 0

  name              = "${local.name_prefix}-ops-alarms"
  kms_master_key_id = "alias/aws/sns"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "ops_alarms_email" {
  count = var.enable_alarms && var.spend_guard_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.ops_alarms[0].arn
  protocol  = "email"
  endpoint  = var.spend_guard_notification_email
}

# HTTP APIs do not publish a 429/throttle metric. Count 429s from the existing
# access log JSON ({ $.status = 429 }) — one custom metric, still inside the
# free-tier custom-metric allowance at this volume.
resource "aws_cloudwatch_log_metric_filter" "api_429" {
  count = var.enable_alarms ? 1 : 0

  name           = "${local.name_prefix}-api-429"
  log_group_name = aws_cloudwatch_log_group.api_access.name
  pattern        = "{ $.status = 429 || $.status = \"429\" }"

  metric_transformation {
    name      = "${local.name_prefix}-api-429-count"
    namespace = "Forge/${local.name_prefix}"
    value     = "1"
  }
}

locals {
  standard_alarms = var.enable_alarms ? {
    lambda_errors = {
      alarm_name          = "${local.name_prefix}-lambda-errors"
      alarm_description   = "Forge API Lambda Errors > 0 over 5 minutes."
      namespace           = "AWS/Lambda"
      metric_name         = "Errors"
      statistic           = "Sum"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 1
      dimensions          = { FunctionName = aws_lambda_function.backend.function_name }
    }
    lambda_throttles = {
      alarm_name          = "${local.name_prefix}-lambda-throttles"
      alarm_description   = "Forge API Lambda Throttles > 0 over 5 minutes."
      namespace           = "AWS/Lambda"
      metric_name         = "Throttles"
      statistic           = "Sum"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 1
      dimensions          = { FunctionName = aws_lambda_function.backend.function_name }
    }
    apigw_5xx = {
      alarm_name          = "${local.name_prefix}-apigw-5xx"
      alarm_description   = "HTTP API 5xx > 0 over 5 minutes."
      namespace           = "AWS/ApiGateway"
      metric_name         = "5xx"
      statistic           = "Sum"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 1
      dimensions = {
        ApiId = aws_apigatewayv2_api.http.id
        Stage = aws_apigatewayv2_stage.default.name
      }
    }
    lambda_concurrent = {
      alarm_name          = "${local.name_prefix}-lambda-concurrent-executions"
      alarm_description   = "Account ConcurrentExecutions Maximum at or above 80% of var.account_concurrency_limit. Check with: aws lambda get-account-settings"
      namespace           = "AWS/Lambda"
      metric_name         = "ConcurrentExecutions"
      statistic           = "Maximum"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = var.account_concurrency_limit * 0.8
      dimensions          = {}
    }
    apigw_429 = {
      alarm_name          = "${local.name_prefix}-apigw-429"
      alarm_description   = "HTTP API access logs recorded a 429 in the last 5 minutes. Raise var.api_throttling_rate_limit / var.api_throttling_burst_limit."
      namespace           = "Forge/${local.name_prefix}"
      metric_name         = "${local.name_prefix}-api-429-count"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      dimensions          = {}
    }
    dynamodb_throttled = {
      alarm_name          = "${local.name_prefix}-dynamodb-throttled-requests"
      alarm_description   = "DynamoDB ThrottledRequests > 0 over 5 minutes (on-demand table; usually a hot partition)."
      namespace           = "AWS/DynamoDB"
      metric_name         = "ThrottledRequests"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      dimensions          = { TableName = aws_dynamodb_table.app_data.name }
    }
    dynamodb_system_errors = {
      alarm_name          = "${local.name_prefix}-dynamodb-system-errors"
      alarm_description   = "DynamoDB SystemErrors > 0 over 5 minutes."
      namespace           = "AWS/DynamoDB"
      metric_name         = "SystemErrors"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      dimensions          = { TableName = aws_dynamodb_table.app_data.name }
    }
    estimated_charges = {
      alarm_name          = "${local.name_prefix}-estimated-charges"
      alarm_description   = "Account EstimatedCharges at or above the spend-guard USD limit. Billing metrics exist only in us-east-1; enable Receive Billing Alerts in the account."
      namespace           = "AWS/Billing"
      metric_name         = "EstimatedCharges"
      statistic           = "Maximum"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = var.spend_guard_limit_usd
      dimensions          = { Currency = "USD" }
    }
  } : {}
}

resource "aws_cloudwatch_metric_alarm" "standard" {
  for_each = local.standard_alarms

  alarm_name          = each.value.alarm_name
  alarm_description   = each.value.alarm_description
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = 1
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  period              = 300
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops_alarms[0].arn]

  dimensions = each.value.dimensions

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_metric_filter.api_429]
}
