# Module 12: CloudWatch, X-Ray, and Alarms

## 1. Concept: Observability and Alerting

Deploying an application is only 10% of the job. The other 90% is knowing if it's broken and exactly *why* it's broken.
- **CloudWatch Logs:** Where the console output (stdout/stderr) of your containers goes.
- **CloudWatch Alarms:** Watches metrics (like CPU or 500-level HTTP errors). If the metric crosses a threshold for a set amount of time, it sends a payload to SNS.
- **SNS (Simple Notification Service):** A pub/sub system. E-mails, Slack bots, or PagerDuty subscribe to an SNS Topic. When an Alarm triggers, SNS blasts the alert to all subscribers.
- **AWS X-Ray:** Distributed tracing. A request hits the ALB, goes to ECS, checks Redis, queries Aurora, and returns. X-Ray draws a visual map showing exactly how many milliseconds each step took.

---

## 2. Code Example: Full-Stack Observability

### Part A: Logs and Dashboards
```hcl
# 1. Log Groups (Never let logs grow infinitely. 30 days is standard)
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${local.prefix}-api"
  retention_in_days = 30
}

# 2. A centralized dashboard for Operations
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "App-Overview"

  # We use jsonencode so we don't have to fiddle with raw string escaping
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0, y = 0, width = 12, height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.external.arn_suffix]
          ]
          period = 300, stat = "Sum", region = "us-east-1", title = "ALB 5xx Errors"
        }
      }
    ]
  })
}

# Save a complex log query so developers can 1-click run it in the console
resource "aws_cloudwatch_query_definition" "api_errors" {
  name = "App/Find-Error-Stacktraces"
  log_group_names = [aws_cloudwatch_log_group.api.name]
  query_string = <<EOF
fields @timestamp, @message
| filter @message like /Exception|Error/
| sort @timestamp desc
| limit 20
EOF
}
```

### Part B: Alarms and Alerts
```hcl
# The "Mailing List"
resource "aws_sns_topic" "alerts" {
  name = "app-high-priority-alerts"
}

# The Subscriber (Sends emails)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "devops-oncall@mycompany.com"
}

# The Alarm: Trigger if ALB sees more than 1% 5xx errors for 2 minutes
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "High-5XX-Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "100" # Assuming > 100 errors a minute is bad
  alarm_description   = "This alarm monitors ALB 500-level errors"
  
  dimensions = {
    LoadBalancer = aws_lb.external.arn_suffix
  }

  # Hook the alarm up to the SNS email topic!
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn] # Send a "Recovered" email
}
```

### Part C: X-Ray Tracing (ECS Sidecar)
To enable X-Ray in Fargate, you run the AWS X-Ray Daemon as a *sidecar* alongside your app.

```hcl
# 1. Update the IAM Task Role from Module 5 to allow X-Ray API calls
resource "aws_iam_policy" "xray" {
  name = "xray-daemon-permissions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
      Resource = ["*"]
    }]
  })
}

# 2. Add the sidecar to the container_definitions in Module 8
# container_definitions = jsonencode([
#   {
#      name = "api-container"
#      ... (your app config)
#   },
#   {
#      name = "xray-daemon"
#      image = "amazon/aws-xray-daemon"
#      cpu = 32
#      memoryReservation = 256
#      portMappings = [{ containerPort = 2000, protocol = "udp" }]
#   }
# ])
```

---

## 3. The "Why": What breaks if I skip this?

* **Skipping `retention_in_days` on Log Groups:** AWS defaults to "Never Expire". After 2 years, your log groups will hold terabytes of stale debugging logs from dev environments, costing the company thousands of dollars a month implicitly. Always cap dev logs to 7-14 days and prod logs to 30-90 days.
* **Skipping `alarm_actions`:** An alarm that goes off in a forest where no one is around does not make a sound. Without tying the alarm to an `aws_sns_topic`, the alarm icon turns red in the AWS console, but no one gets paged. Your site stays down.
* **X-Ray Sidecar without IAM Policy:** The X-Ray daemon will boot up successfully inside Fargate, but every time it tries to send trace data to AWS, AWS will return an HTTP 403 Forbidden. Your logs will fill with X-Ray daemon errors, and you won't see any tracing in the console.

---

## 4. Hands-on Exercise

Notice the `<<EOF ... EOF` syntax in the `aws_cloudwatch_query_definition`. This is called a **Heredoc**.
It allows you to write multi-line strings in Terraform without using `\n` carriage returns. 
If you used `<<-EOF` (with a hyphen), how does the behavior of the heredoc change regarding indentation? 
*(Experiment with heredocs in `terraform console` to find out!)*
