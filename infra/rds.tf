# ─── RDS Subnet Group ─────────────────────────────────────────────────────────
# RDS requires a subnet group spanning at least 2 AZs.
# We use both private subnets so the instance (and any future read replica)
# can be placed in either AZ.

resource "aws_db_subnet_group" "postgres" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Private subnets for RDS PostgreSQL"
  subnet_ids  = aws_subnet.private[*].id

  tags = { Name = "${var.project_name}-${var.environment}-db-subnet-group" }
}

# ─── RDS Parameter Group ──────────────────────────────────────────────────────
# Custom parameter group lets us tune PostgreSQL settings without recreating
# the instance. Currently uses defaults — add parameters here as needed.

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-${var.environment}-pg15"
  family      = "postgres15"
  description = "PostgreSQL 15 parameter group for ${var.project_name}"

  tags = { Name = "${var.project_name}-${var.environment}-pg15" }
}

# ─── RDS Instance ─────────────────────────────────────────────────────────────

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine
  engine               = "postgres"
  engine_version       = "15"
  instance_class       = var.db_instance_class

  # Storage — gp3 is cheaper and faster than gp2
  allocated_storage     = 20
  max_allocated_storage = 100  # auto-scaling upper bound
  storage_type          = "gp3"
  storage_encrypted     = true

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Networking — private only, no public endpoint
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false  # set to true for production HA (+~$15/mo)

  # Configuration
  parameter_group_name = aws_db_parameter_group.postgres.name
  port                 = 5432

  # Backups
  backup_retention_period = 7       # days — 0 disables backups
  backup_window           = "03:00-04:00"  # UTC, low-traffic window
  maintenance_window      = "mon:04:00-mon:05:00"

  skip_final_snapshot = true

  # Prevent accidental deletion via terraform destroy
  # deletion_protection = true

  tags = { Name = "${var.project_name}-${var.environment}-postgres" }
}

# ─── SSM Parameter Store — DATABASE_URL ──────────────────────────────────────
# Store the full connection string as a SecureString so the ECS task definition
# can inject it as an environment variable without it appearing in plaintext.
# SecureString encrypts with the account's default SSM KMS key at no extra cost.
# Cheaper than Secrets Manager ($0/month vs $0.40/secret/month).

resource "aws_ssm_parameter" "db_url" {
  name        = "/${var.project_name}/${var.environment}/database-url"
  description = "PostgreSQL connection string for competitive intelligence app"
  type        = "SecureString"
  value       = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:5432/${var.db_name}"

  tags = { Name = "${var.project_name}-${var.environment}-db-url" }
}
