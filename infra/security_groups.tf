# ─── Security Groups ──────────────────────────────────────────────────────────
# ALB and ECS SGs reference each other, so rules that cross-reference
# are defined as separate aws_security_group_rule resources to avoid
# a Terraform circular dependency.

# ─── ALB ──────────────────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB: allow HTTP/HTTPS inbound from internet"
  vpc_id      = aws_vpc.main.id

  # HTTP — redirects to HTTPS (listener rule added in alb.tf)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-alb-sg" }
}

# ALB → ECS on Streamlit port (separate rule to avoid circular dependency)
resource "aws_security_group_rule" "alb_egress_to_ecs" {
  type                     = "egress"
  description              = "Forward to ECS tasks on Streamlit port"
  security_group_id        = aws_security_group.alb.id
  from_port                = 8501
  to_port                  = 8501
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
}

# ─── ECS Tasks ────────────────────────────────────────────────────────────────

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-${var.environment}-ecs-sg"
  description = "ECS tasks: inbound from ALB, all outbound for Bedrock and DuckDuckGo"
  vpc_id      = aws_vpc.main.id

  # All outbound: ECS tasks need to reach AWS Bedrock (HTTPS), DuckDuckGo,
  # RDS (5432), and EFS (2049)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-ecs-sg" }
}

# ECS inbound from ALB (separate rule to avoid circular dependency)
resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  type                     = "ingress"
  description              = "Streamlit from ALB"
  security_group_id        = aws_security_group.ecs.id
  from_port                = 8501
  to_port                  = 8501
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

# ─── RDS ──────────────────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "RDS PostgreSQL: allow only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = { Name = "${var.project_name}-${var.environment}-rds-sg" }
}

# ─── EFS ──────────────────────────────────────────────────────────────────────

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-${var.environment}-efs-sg"
  description = "EFS: allow NFS only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = { Name = "${var.project_name}-${var.environment}-efs-sg" }
}
