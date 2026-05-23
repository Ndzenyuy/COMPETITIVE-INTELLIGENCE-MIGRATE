# ─── Project ──────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "ci"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into (minimum 2 required for RDS)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB lives here)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (ECS, RDS, EFS live here)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ─── Database ─────────────────────────────────────────────────────────────────

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "competitive_intelligence"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL master password — set via TF_VAR_db_password env var, never commit this"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

# ─── ECS — Dashboard ──────────────────────────────────────────────────────────

variable "dashboard_cpu" {
  description = "Fargate CPU units for the dashboard task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "dashboard_memory" {
  description = "Fargate memory (MB) for the dashboard task"
  type        = number
  default     = 1024
}

# ─── ECS — Agent ──────────────────────────────────────────────────────────────

variable "agent_cpu" {
  description = "Fargate CPU units for the agent task"
  type        = number
  default     = 1024
}

variable "agent_memory" {
  description = "Fargate memory (MB) for the agent task (needs headroom for sentence-transformers)"
  type        = number
  default     = 2048
}

variable "agent_schedule" {
  description = "EventBridge cron expression for the agent run schedule"
  type        = string
  default     = "cron(0 9 ? * MON *)"
}

variable "agent_max_iterations" {
  description = "Max agentic loop iterations per competitor"
  type        = number
  default     = 8
}

# ─── ALB / HTTPS ──────────────────────────────────────────────────────────────

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. Leave empty to use HTTP only (good for initial setup). Request a free cert in ACM for your domain and set this to enable HTTPS."
  type        = string
  default     = ""
}

# ─── Alerting ─────────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications. Leave empty to create the SNS topic without a subscription."
  type        = string
  default     = ""
}

# ─── CI/CD ────────────────────────────────────────────────────────────────────

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. jones/competitive-intelligence-migrate). Used to scope the OIDC role so only your repo's main branch can assume it."
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy. Set to the git SHA by CI/CD (e.g. sha-abc1234). Defaults to 'latest' for local terraform apply runs."
  type        = string
  default     = "latest"
}
