# ─── EventBridge Scheduled Rule ───────────────────────────────────────────────
# Fires on the schedule defined by var.agent_schedule (default: Mondays 9am UTC)
# and launches the agent ECS task to research all competitors.

resource "aws_cloudwatch_event_rule" "agent_schedule" {
  name                = "${var.project_name}-${var.environment}-agent-schedule"
  description         = "Weekly trigger for competitive intelligence agent"
  schedule_expression = var.agent_schedule
  state               = "ENABLED"

  tags = { Name = "${var.project_name}-${var.environment}-agent-schedule" }
}

# ─── EventBridge Target → ECS Task ────────────────────────────────────────────
# Launches the agent task definition as a Fargate task in a private subnet.
# The EventBridge role (iam.tf) allows this rule to call ecs:RunTask and
# iam:PassRole when it fires.

resource "aws_cloudwatch_event_target" "agent_task" {
  rule      = aws_cloudwatch_event_rule.agent_schedule.name
  target_id = "${var.project_name}-${var.environment}-agent-task"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.agent.arn
    task_count          = 1
    launch_type         = "FARGATE"

    # Run in a private subnet — outbound goes through NAT to reach
    # Bedrock and DuckDuckGo, same as the dashboard task
    network_configuration {
      subnets          = aws_subnet.private[*].id
      security_groups  = [aws_security_group.ecs.id]
      assign_public_ip = false
    }
  }
}
