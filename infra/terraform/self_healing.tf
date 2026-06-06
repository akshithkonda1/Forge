data "archive_file" "healer_lambda" {
  count       = var.enable_self_healing ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/healer/handler.py"
  output_path = "${path.module}/build/forge-healer.zip"
}

data "aws_iam_policy_document" "healer_assume_role" {
  count = var.enable_self_healing ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "healer_lambda" {
  count = var.enable_self_healing ? 1 : 0

  statement {
    sid = "CloudWatchLogs"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-healer:*",
    ]
  }

  statement {
    sid = "RedeployApiLambda"

    actions = [
      "lambda:GetFunction",
      "lambda:UpdateFunctionCode",
      "lambda:PublishVersion",
    ]

    resources = [
      aws_lambda_function.backend.arn,
      "${aws_lambda_function.backend.arn}:*",
    ]
  }

  statement {
    sid = "ReadLambdaArtifacts"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]

    resources = [
      "${aws_s3_bucket.artifacts.arn}/lambda/*",
    ]
  }

  statement {
    sid = "EmitHealthMetrics"

    actions = [
      "cloudwatch:PutMetricData",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Forge/SelfHealing"]
    }
  }
}

resource "aws_cloudwatch_log_group" "healer_lambda" {
  count             = var.enable_self_healing ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-healer"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_iam_role" "healer_lambda" {
  count              = var.enable_self_healing ? 1 : 0
  name               = "${local.name_prefix}-healer"
  assume_role_policy = data.aws_iam_policy_document.healer_assume_role[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "healer_lambda" {
  count  = var.enable_self_healing ? 1 : 0
  name   = "${local.name_prefix}-healer"
  role   = aws_iam_role.healer_lambda[0].id
  policy = data.aws_iam_policy_document.healer_lambda[0].json
}

resource "aws_lambda_function" "healer" {
  count         = var.enable_self_healing ? 1 : 0
  function_name = "${local.name_prefix}-healer"
  role          = aws_iam_role.healer_lambda[0].arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.healer_lambda[0].output_path
  source_code_hash = data.archive_file.healer_lambda[0].output_base64sha256

  environment {
    variables = {
      ARTIFACTS_BUCKET             = aws_s3_bucket.artifacts.bucket
      ARTIFACTS_KEY                = aws_s3_object.backend_lambda.key
      HEALTH_CHECK_TIMEOUT_SECONDS = tostring(var.health_check_timeout_seconds)
      HEALTH_CHECK_URL             = "${aws_apigatewayv2_api.http.api_endpoint}/health"
      METRIC_NAMESPACE             = "Forge/SelfHealing"
      TARGET_FUNCTION_NAME         = aws_lambda_function.backend.function_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.healer_lambda,
    aws_iam_role_policy.healer_lambda,
  ]

  tags = local.common_tags
}

resource "aws_sns_topic" "ops_alerts" {
  count = var.enable_self_healing ? 1 : 0
  name  = "${local.name_prefix}-ops-alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "ops_email" {
  count     = var.enable_self_healing && var.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.ops_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "api_health" {
  count               = var.enable_self_healing ? 1 : 0
  alarm_name          = "${local.name_prefix}-api-health"
  alarm_description   = "Forge API health probe failed — healer will attempt redeploy from S3 artifact."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApiHealthStatus"
  namespace           = "Forge/SelfHealing"
  period              = max(var.health_check_interval_minutes * 60, 60)
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    FunctionName = aws_lambda_function.backend.function_name
  }

  alarm_actions = [aws_sns_topic.ops_alerts[0].arn]
  ok_actions    = [aws_sns_topic.ops_alerts[0].arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_self_healing ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-errors"
  alarm_description   = "Forge API Lambda error rate exceeded threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.backend.function_name
  }

  alarm_actions = [aws_sns_topic.ops_alerts[0].arn]
  ok_actions    = [aws_sns_topic.ops_alerts[0].arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "health_probe_schedule" {
  count               = var.enable_self_healing ? 1 : 0
  name                = "${local.name_prefix}-health-probe"
  description         = "Periodic Forge API health probe and self-healing redeploy."
  schedule_expression = "rate(${var.health_check_interval_minutes} minutes)"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "health_probe_healer" {
  count     = var.enable_self_healing ? 1 : 0
  rule      = aws_cloudwatch_event_rule.health_probe_schedule[0].name
  target_id = "forge-healer"
  arn       = aws_lambda_function.healer[0].arn
}

resource "aws_lambda_permission" "eventbridge_health_probe" {
  count         = var.enable_self_healing ? 1 : 0
  statement_id  = "AllowEventBridgeHealthProbe"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.healer[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_probe_schedule[0].arn
}

resource "aws_cloudwatch_event_rule" "lambda_error_alarm" {
  count       = var.enable_self_healing ? 1 : 0
  name        = "${local.name_prefix}-lambda-error-recover"
  description = "Trigger healer when the API Lambda error alarm enters ALARM."

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "lambda_error_healer" {
  count     = var.enable_self_healing ? 1 : 0
  rule      = aws_cloudwatch_event_rule.lambda_error_alarm[0].name
  target_id = "forge-healer-recover"
  arn       = aws_lambda_function.healer[0].arn

  input = jsonencode({
    source       = "cloudwatch-alarm"
    forceRecover = true
  })
}

resource "aws_lambda_permission" "eventbridge_lambda_error" {
  count         = var.enable_self_healing ? 1 : 0
  statement_id  = "AllowEventBridgeLambdaErrorRecover"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.healer[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_error_alarm[0].arn
}