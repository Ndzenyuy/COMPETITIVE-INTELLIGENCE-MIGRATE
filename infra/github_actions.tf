# ─── GitHub Actions OIDC Provider ────────────────────────────────────────────
# Looks up the existing GitHub OIDC provider (only one is allowed per AWS account).
# If it doesn't exist yet, the resource block below creates it.
# On first run in a fresh account, comment out the data source and let the
# resource create it; on subsequent runs the import step in bootstrap.yml
# ensures Terraform manages the existing one without trying to recreate it.

data "aws_iam_openid_connect_provider" "github_actions_existing" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = data.aws_iam_openid_connect_provider.github_actions_existing.arn
}

# ─── GitHub Actions IAM Role ──────────────────────────────────────────────────
# The condition locks this role to your repository's main branch only.
# A fork or feature branch cannot assume it — only pushes to main trigger deploy.

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.environment}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.github_oidc_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Only the main branch of your repo can assume this role
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = { Name = "${var.project_name}-${var.environment}-github-actions-role" }
}

# PowerUserAccess covers all AWS service APIs (ECR, ECS, RDS, EFS, ALB, etc.)
# except IAM user management. Sufficient for Terraform to manage all resources
# in this project except IAM resources (handled by the inline policy below).
resource "aws_iam_role_policy_attachment" "github_actions_power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# IAM operations Terraform needs to create roles and policies.
# Scoped to exactly the actions used across iam.tf and github_actions.tf.
resource "aws_iam_role_policy" "github_actions_iam" {
  name = "terraform-iam-operations"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "TerraformIAMOperations"
      Effect = "Allow"
      Action = [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:PassRole",
        "iam:CreateOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders"
      ]
      Resource = "*"
    }]
  })
}

# ─── Output ───────────────────────────────────────────────────────────────────
# After the first `terraform apply`, copy this ARN and store it in GitHub:
# Settings → Secrets and variables → Actions → New secret → AWS_ROLE_ARN

output "github_actions_role_arn" {
  description = "Add this as GitHub secret AWS_ROLE_ARN to enable CI/CD"
  value       = aws_iam_role.github_actions.arn
}
