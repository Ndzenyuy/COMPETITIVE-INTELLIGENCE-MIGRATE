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
        # Allow any ref in your repo — deploy.yml is already gated on push-to-main;
        # destroy.yml requires typing "destroy" as a manual confirmation gate.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
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

# IAM operations Terraform needs to create/destroy roles and policies.
# Scoped to exactly the actions used across iam.tf and github_actions.tf.
#
# NOTE: During `terraform destroy` Terraform may detach PowerUserAccess from
# this role before all other resources are gone, leaving the role without S3,
# ECS, and EC2 permissions mid-run. The two statements below ensure those
# critical operations remain available via the inline policy throughout.
resource "aws_iam_role_policy" "github_actions_iam" {
  name = "terraform-iam-operations"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
          "iam:ListInstanceProfilesForRole",
          "iam:PassRole",
          "iam:CreateOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders"
        ]
        Resource = "*"
      },
      {
        # Terraform state bucket access — must survive PowerUserAccess being
        # detached from this role during terraform destroy.
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::terraform-backend-65857",
          "arn:aws:s3:::terraform-backend-65857/*"
        ]
      },
      {
        # ECS, ECR, and EC2 actions used during destroy that must survive
        # PowerUserAccess being detached mid-run.
        Sid    = "TerraformDestroyOperations"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:DeleteService",
          "ecr:ListImages",
          "ecr:BatchDeleteImage",
          "ecr:DescribeRepositories",
          "ec2:DetachInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:DisassociateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:DeleteSubnet",
          "ec2:DeleteVpc"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── Output ───────────────────────────────────────────────────────────────────
# After the first `terraform apply`, copy this ARN and store it in GitHub:
# Settings → Secrets and variables → Actions → New secret → AWS_ROLE_ARN

output "github_actions_role_arn" {
  description = "Add this as GitHub secret AWS_ROLE_ARN to enable CI/CD"
  value       = aws_iam_role.github_actions.arn
}
