# ─── Application Load Balancer ────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Protects against accidental deletion via console or terraform destroy
  enable_deletion_protection = true

  tags = { Name = "${var.project_name}-${var.environment}-alb" }
}

# ─── Target Group ─────────────────────────────────────────────────────────────
# IP target type is required for Fargate (tasks have no stable instance ID).
# Streamlit exposes a health endpoint at /_stcore/health → returns HTTP 200.

resource "aws_lb_target_group" "dashboard" {
  name        = "${var.project_name}-${var.environment}-dashboard-tg"
  port        = 8501
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/_stcore/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Allow in-flight requests to complete before deregistering a task
  deregistration_delay = 30

  tags = { Name = "${var.project_name}-${var.environment}-dashboard-tg" }
}

# ─── HTTP Listener (port 80) ──────────────────────────────────────────────────
# If a certificate ARN is provided, redirect HTTP → HTTPS.
# Otherwise, forward directly to the target group (useful before cert setup).

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.dashboard.arn
    }
  }
}

# ─── HTTPS Listener (port 443) ────────────────────────────────────────────────
# Created only when certificate_arn is provided.
# To add HTTPS: request a free cert in ACM for your domain, then set
# certificate_arn in terraform.tfvars and re-apply.

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }
}
