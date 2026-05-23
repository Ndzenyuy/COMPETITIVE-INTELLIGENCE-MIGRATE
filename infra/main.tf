terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend configuration — all values are passed via -backend-config
  # flags at `terraform init` time by bootstrap.yml and deploy.yml.
  # This avoids hardcoding the account-specific bucket name in source control.
  backend "s3" {
    bucket               = "terraform-backend-65857"
    key                  = "testapp/terraform.tfstate"
    region               = "us-east-1"
    encrypt              = true
    use_lockfile         = true
    workspace_key_prefix = "environments"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Fetch current AWS account ID and region (used in IAM policies and ARNs)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
