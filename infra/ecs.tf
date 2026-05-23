# ─── CloudWatch Log Groups ────────────────────────────────────────────────────
# Created here (referenced by task definitions below).
# Step 6 (cloudwatch.tf) adds metric filters and alarms on top of these groups.

resource "aws_cloudwatch_log_group" "dashboard" {
  name              = "/ecs/${var.project_name}-${var.environment}/dashboard"
  retention_in_days = 30

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-logs" }
}

resource "aws_cloudwatch_log_group" "agent" {
  name              = "/ecs/${var.project_name}-${var.environment}/agent"
  retention_in_days = 30

  tags = { Name = "${var.project_name}-${var.environment}-agent-logs" }
}

# ─── ECS Cluster ──────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  # Container Insights adds CPU/memory metrics to CloudWatch at ~$0.50/month
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project_name}-${var.environment}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ─── Dashboard Task Definition ────────────────────────────────────────────────

resource "aws_ecs_task_definition" "dashboard" {
  family                   = "${var.project_name}-${var.environment}-dashboard"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.dashboard_cpu
  memory                   = var.dashboard_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "dashboard"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = 8501
      protocol      = "tcp"
    }]

    # Non-secret configuration passed as plaintext env vars
    environment = [
      { name = "CHROMA_PATH",        value = "/mnt/efs" },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region }
    ]

    # DATABASE_URL is pulled from SSM Parameter Store at container start.
    # The execution role's ssm:GetParameters permission makes this possible.
    secrets = [{
      name      = "DATABASE_URL"
      valueFrom = aws_ssm_parameter.db_url.arn
    }]

    mountPoints = [{
      sourceVolume  = "chroma-efs"
      containerPath = "/mnt/efs"
      readOnly      = false
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.dashboard.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  # EFS volume — the access point scopes the container to /chroma_data on EFS
  volume {
    name = "chroma-efs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.chroma.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.chroma.id
        iam             = "DISABLED"
      }
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-task" }
}

# ─── Agent Task Definition ────────────────────────────────────────────────────
# Same image as dashboard, different command.
# Higher CPU and memory because sentence-transformers runs inference here.

resource "aws_ecs_task_definition" "agent" {
  family                   = "${var.project_name}-${var.environment}-agent"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.agent_cpu
  memory                   = var.agent_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "agent"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    # Override the Dockerfile CMD to run the agent script instead of Streamlit
    command = ["python", "scripts/run_multiple.py"]

    environment = [
      { name = "CHROMA_PATH",        value = "/mnt/efs" },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region }
    ]

    secrets = [{
      name      = "DATABASE_URL"
      valueFrom = aws_ssm_parameter.db_url.arn
    }]

    mountPoints = [{
      sourceVolume  = "chroma-efs"
      containerPath = "/mnt/efs"
      readOnly      = false
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.agent.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  volume {
    name = "chroma-efs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.chroma.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.chroma.id
        iam             = "DISABLED"
      }
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-agent-task" }
}

# ─── ECS Service (Dashboard) ──────────────────────────────────────────────────
# Keeps one dashboard task running at all times and registers it with the ALB.
# The agent task is NOT a service — it is launched on-demand by EventBridge
# (configured in Step 6: eventbridge.tf).

resource "aws_ecs_service" "dashboard" {
  name            = "${var.project_name}-${var.environment}-dashboard"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.dashboard.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true  # public IP replaces NAT gateway for outbound traffic
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dashboard.arn
    container_name   = "dashboard"
    container_port   = 8501
  }

  # Give Streamlit 2 minutes to start before the ALB marks it unhealthy
  health_check_grace_period_seconds = 120

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # Ensure EFS mount targets are ready in all AZs before the first task starts
  depends_on = [
    aws_efs_mount_target.chroma,
    aws_lb_listener.http
  ]

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-svc" }
}
