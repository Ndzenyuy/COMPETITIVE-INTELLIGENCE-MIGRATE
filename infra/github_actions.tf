# ─── GitHub Actions OIDC Provider ────────────────────────────────────────────
# Allows GitHub Actions to assume an AWS IAM role without storing static
# access keys as GitHub secrets. The OIDC token proves the job is running
# in your specific repository before AWS issues temporary credentials.

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]

  # Thumbprints for the GitHub OIDC TLS certificate chain.
  # These are stable but can be updated via:
  # openssl s_client -servername token.actions.githubusercontent.com \
  #   -connect token.actions.githubusercontent.com:443 < /dev/null 2>/dev/null \
  #   | openssl x509 -fingerprint -noout -sha1
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = { Name = "${var.project_name}-${var.environment}-github-oidc" }
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
        Federated = aws_iam_openid_connect_provider.github_actions.arn
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
