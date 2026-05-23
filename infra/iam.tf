# ─── Shared Trust Policies ────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_task_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "events_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# ─── ECS Task Execution Role ──────────────────────────────────────────────────
# Used by the ECS infrastructure (not your code) to:
#   - Pull the container image from ECR
#   - Write container logs to CloudWatch
#   - Fetch SSM SecureString parameters to inject as env vars at container start

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-${var.environment}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json

  tags = { Name = "${var.project_name}-${var.environment}-ecs-exec-role" }
}

# Managed policy covers ECR image pull + CloudWatch log stream creation
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to decrypt and fetch the DATABASE_URL SSM parameter
resource "aws_iam_role_policy" "ecs_task_execution_ssm" {
  name = "read-ssm-db-url"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadDatabaseUrl"
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = [aws_ssm_parameter.db_url.arn]
    }]
  })
}

# ─── ECS Task Role ────────────────────────────────────────────────────────────
# Used by the running application code (boto3 in agent/loop.py and dashboard).
# boto3 auto-detects this role via the ECS container metadata endpoint —
# no AWS credentials needed in .env.

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-${var.environment}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json

  tags = { Name = "${var.project_name}-${var.environment}-ecs-task-role" }
}

resource "aws_iam_role_policy" "ecs_task_bedrock" {
  name = "invoke-bedrock"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "InvokeClaude"
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:Converse"  # dashboard/app.py uses bedrock.converse()
      ]
      # Cross-region inference profiles require TWO resource ARNs:
      # 1. The inference profile itself (account-scoped, specific region)
      # 2. The underlying foundation model (no account ID, wildcard region)
      #    Bedrock checks both when routing through a cross-region profile.
      Resource = [
        "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-sonnet-4-6",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-6"
      ]
    }]
  })
}

# ─── EventBridge Role ─────────────────────────────────────────────────────────
# Allows EventBridge Scheduler to launch the agent ECS task on a cron schedule.
# iam:PassRole is required so EventBridge can hand the task and execution roles
# to the newly launched Fargate task.

resource "aws_iam_role" "eventbridge" {
  name               = "${var.project_name}-${var.environment}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.events_trust.json

  tags = { Name = "${var.project_name}-${var.environment}-eventbridge-role" }
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "run-agent-task"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RunAgentTask"
        Effect = "Allow"
        Action = ["ecs:RunTask"]
        Resource = [
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.project_name}-${var.environment}-agent:*"
        ]
        Condition = {
          ArnLike = {
            "ecs:cluster" = aws_ecs_cluster.main.arn
          }
        }
      },
      {
        Sid    = "PassRolesToTask"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
      }
    ]
  })
}
