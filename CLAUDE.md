# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a scaffold for migrating a **Competitive Intelligence Platform** to AWS ECS Fargate. The project is in an active migration state — infrastructure stubs exist but the application code (`app/`) has not yet been added (Step 2 of the delivery plan).

## Local Development

```bash
# Build and run locally
docker build -t ci-local .
docker run -p 8501:8501 --env-file .env ci-local
# Access dashboard at http://localhost:8501
```

Copy `.env.example` to `.env` and fill in values before running.

## Infrastructure Deployment

All infrastructure lives in `infra/`. Terraform >= 1.6 required.

```bash
cd infra
terraform init
terraform plan
terraform apply
```

The `infra/` stub files (`vpc.tf`, `security_groups.tf`, `rds.tf`, `efs.tf`, `ecr.tf`, `iam.tf`, `alb.tf`, `ecs.tf`, `eventbridge.tf`, `cloudwatch.tf`) need implementation. `main.tf`, `variables.tf`, and `outputs.tf` are complete.

To enable remote Terraform state, uncomment the S3 backend block in `infra/main.tf` and create the S3 bucket + DynamoDB table first.

## Architecture

Two ECS workloads run from a single Docker image:
- **ci-dashboard** — Streamlit web app, persistent ECS Service behind an ALB on port 8501
- **ci-agent** — Batch Python job triggered weekly via EventBridge (Monday 9am UTC), runs `python scripts/run_multiple.py`

**Data stores:**
- **RDS PostgreSQL 15** (`db.t3.micro`) — signals and metadata, connection via `DATABASE_URL` env var
- **EFS** — ChromaDB vector database, mounted at `/mnt/efs/chroma_data`, path set via `CHROMA_PATH` env var

**Networking:**
- VPC `10.0.0.0/16` with public subnets (ALB only) and private subnets (ECS, RDS, EFS)
- NAT Gateway provides outbound internet access from private subnets (for Bedrock API, web scraping)
- Four security groups: ALB, ECS, RDS, EFS

**AWS Bedrock** (Claude) is used for RAG and agent functionality from within ECS tasks.

## Required Code Change When Migrating App Code

When `app/` code is migrated, update `app/rag/embeddings.py` line 24:

```python
# Before
chroma_client = chromadb.PersistentClient(path="./chroma_data")

# After
chroma_client = chromadb.PersistentClient(path=os.getenv("CHROMA_PATH", "./chroma_data"))
```

## CI/CD

`.github/workflows/deploy.yml` is a stub. The full pipeline (push to main) should:
1. Build Docker image and push to ECR
2. Run `terraform apply`
3. Force a new ECS deployment

GitHub Actions uses OIDC federation — no static AWS keys. Required secrets: `AWS_ROLE_ARN`, `TF_VAR_db_password`.

## Environment Variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | RDS PostgreSQL connection string |
| `CHROMA_PATH` | ChromaDB persistence path (default: `./chroma_data`) |
| `AWS_DEFAULT_REGION` | AWS region for Bedrock API calls |

## Delivery Plan Status

The README.md tracks an 8-step delivery plan. Steps 3–8 (Terraform implementations, CI/CD, and verification) are pending. When implementing Terraform resources, follow the variable definitions in `infra/variables.tf` and the expected outputs in `infra/outputs.tf`.
