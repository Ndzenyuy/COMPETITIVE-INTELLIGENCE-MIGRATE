# ─── Outputs ──────────────────────────────────────────────────────────────────
# These are populated after `terraform apply` and printed to the terminal.
# Use them to configure DNS, update secrets, or verify the deployment.

output "alb_dns_name" {
  description = "Public DNS of the Application Load Balancer — point your domain here"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL — used in CI/CD to push the Docker image"
  value       = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  description = "RDS hostname — used to build DATABASE_URL"
  value       = aws_db_instance.postgres.address
  sensitive   = true
}

output "efs_id" {
  description = "EFS filesystem ID — useful for manual inspection or mount"
  value       = aws_efs_file_system.chroma.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name — used in deploy scripts and EventBridge targets"
  value       = aws_ecs_cluster.main.name
}

output "dashboard_task_definition_arn" {
  description = "ARN of the dashboard task definition"
  value       = aws_ecs_task_definition.dashboard.arn
}

output "agent_task_definition_arn" {
  description = "ARN of the agent task definition"
  value       = aws_ecs_task_definition.agent.arn
}

output "public_subnet_ids" {
  description = "Public subnet IDs — used to launch ECS tasks (dashboard, agent, migration)"
  value       = join(",", aws_subnet.public[*].id)
}

output "ecs_security_group_id" {
  description = "ECS security group ID — used to launch one-off tasks with RDS access"
  value       = aws_security_group.ecs.id
}
