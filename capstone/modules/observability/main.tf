resource "aws_sns_topic" "alerts" {
  name = "${var.prefix}-alerts"
  # tfsec:ignore:aws-sns-enable-topic-encryption
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.prefix}-High-5XX-Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "Monitors ALB 500-level errors"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0, y = 0, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
          period = 300, stat = "Sum", region = "us-east-1", title = "ALB 5xx Errors"
        }
      }
    ]
  })
}
