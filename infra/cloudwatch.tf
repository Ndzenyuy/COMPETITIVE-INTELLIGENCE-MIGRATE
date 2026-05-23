# ─── SNS Topic for Alerts ─────────────────────────────────────────────────────
# All alarms below publish to this topic.
# Set var.alert_email to receive notifications — you'll get a confirmation email
# after the first terraform apply that you must click to activate.

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = { Name = "${var.project_name}-${var.environment}-alerts" }
}

resource "aws_sns_topic_subscription" "alert_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─── Dashboard: CPU Alarm ─────────────────────────────────────────────────────
# Fires when the dashboard container uses > 80% CPU for 2 consecutive minutes.
# Usually indicates a runaway chat request or Streamlit reloading repeatedly.

resource "aws_cloudwatch_metric_alarm" "dashboard_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-dashboard-cpu-high"
  alarm_description   = "Dashboard CPU above 80% — possible runaway process"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.dashboard.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-cpu-alarm" }
}

# ─── Dashboard: Memory Alarm ──────────────────────────────────────────────────
# Fires when memory exceeds 80% of the task's allocated 1GB.
# At ~820 MB usage the task is close to OOM — action: increase dashboard_memory.

resource "aws_cloudwatch_metric_alarm" "dashboard_memory_high" {
  alarm_name          = "${var.project_name}-${var.environment}-dashboard-memory-high"
  alarm_description   = "Dashboard memory above 80% — consider increasing dashboard_memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.dashboard.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-memory-alarm" }
}

# ─── Dashboard: No Healthy Hosts ──────────────────────────────────────────────
# Fires when the ALB has zero healthy targets — the dashboard is completely down.
# Causes: task crash, failed deployment, OOM kill, EFS mount failure.

resource "aws_cloudwatch_metric_alarm" "dashboard_no_healthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-dashboard-no-healthy-hosts"
  alarm_description   = "No healthy dashboard tasks behind the ALB — dashboard is down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.dashboard.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-healthy-hosts-alarm" }
}

# ─── Dashboard: ALB 5XX Errors ────────────────────────────────────────────────
# Fires when the app returns 5XX errors more than 10 times in 5 minutes.
# Catches application exceptions surfacing through Streamlit.

resource "aws_cloudwatch_metric_alarm" "dashboard_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-dashboard-5xx-errors"
  alarm_description   = "Dashboard returning 5XX errors — check application logs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.dashboard.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-5xx-alarm" }
}

# ─── Agent: Failure Metric Filter ─────────────────────────────────────────────
# The agent script logs "✗ <competitor> failed: ..." on errors (run_multiple.py).
# This metric filter counts those lines and the alarm fires if any competitor
# fails in a single agent run.

resource "aws_cloudwatch_log_metric_filter" "agent_failures" {
  name           = "${var.project_name}-${var.environment}-agent-failures"
  log_group_name = aws_cloudwatch_log_group.agent.name
  pattern        = "\"failed\""

  metric_transformation {
    name      = "AgentCompetitorFailures"
    namespace = "${var.project_name}/${var.environment}"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "agent_failures" {
  alarm_name          = "${var.project_name}-${var.environment}-agent-failures"
  alarm_description   = "One or more competitors failed during the agent run — check agent logs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "AgentCompetitorFailures"
  namespace           = "${var.project_name}/${var.environment}"
  period              = 3600
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project_name}-${var.environment}-agent-failure-alarm" }
}
