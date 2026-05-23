# Competitive Intelligence — ECS Migration

Automated deployment of the Competitive Intelligence Platform to AWS ECS Fargate using Terraform.

## Architecture

```
Internet (HTTPS 443)
        │
        ▼
┌───────────────┐
│      ALB      │  ← public subnets
└───────┬───────┘
        │ port 8501
        ▼
┌───────────────────┐        ┌─────────────────┐
│  ECS Service      │        │  ECS Task       │
│  ci-dashboard     │        │  ci-agent       │
│  (always-on)      │        │  (weekly cron)  │
└────────┬──────────┘        └───────┬─────────┘
         │                           │
         └──────────┬────────────────┘
                    │  private subnets
         ┌──────────┼─────────────┐
         ▼          ▼             ▼
      RDS         EFS          Bedrock
   PostgreSQL  (ChromaDB)    (Claude API)
```

**Two ECS workloads from one Docker image:**
- `ci-dashboard` — Streamlit app, runs as an ECS Service (always-on), served via ALB
- `ci-agent` — `scripts/run_multiple.py`, runs as a Fargate task on a weekly EventBridge schedule

---

## Step-by-Step Delivery Plan

### Step 1 — Repository Setup ✅ (current)
**What:** Project skeleton, Dockerfile, Terraform variable definitions, CI/CD placeholder.

**Files created:**
```
COMPETITIVE-INTELLIGENCE-MIGRATE/
├── app/                        ← app code goes here (Step 2)
├── infra/
│   ├── main.tf                 ← Terraform provider + backend config
│   ├── variables.tf            ← all input variables defined
│   ├── outputs.tf              ← outputs declared (ALB DNS, ECR URL, etc.)
│   ├── terraform.tfvars.example
│   ├── vpc.tf                  ← stub (Step 3)
│   ├── security_groups.tf      ← stub (Step 3)
│   ├── rds.tf                  ← stub (Step 4)
│   ├── efs.tf                  ← stub (Step 4)
│   ├── ecr.tf                  ← stub (Step 5)
│   ├── iam.tf                  ← stub (Step 5)
│   ├── alb.tf                  ← stub (Step 5)
│   ├── ecs.tf                  ← stub (Step 5)
│   ├── eventbridge.tf          ← stub (Step 6)
│   └── cloudwatch.tf           ← stub (Step 6)
├── .github/workflows/deploy.yml← stub (Step 7)
├── Dockerfile
├── .gitignore
├── .env.example
└── README.md
```

**Prerequisites to install before Step 3:**
- [Terraform >= 1.6](https://developer.hashicorp.com/terraform/install)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) + `aws configure`
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

---

### Step 2 — Migrate Application Code
**What:** Copy app from the original project into `app/`, apply the one required code change.

**Actions:**
1. Copy all source directories into `app/`:
   `agent/`, `dashboard/`, `db/`, `evals/`, `extractor/`, `prompts/`, `rag/`, `scraper/`, `scripts/`, `.streamlit/`, `main.py`, `requirements.txt`

2. Apply the **one required code change** in `app/rag/embeddings.py` line 24:
   ```python
   # Before
   chroma_client = chromadb.PersistentClient(path="./chroma_data")

   # After — reads path from env var, defaults to ./chroma_data for local dev
   chroma_client = chromadb.PersistentClient(path=os.getenv("CHROMA_PATH", "./chroma_data"))
   ```

3. Verify Docker build works locally:
   ```bash
   docker build -t ci-local .
   docker run -p 8501:8501 --env-file .env ci-local
   ```

**Why EFS needs this:** ECS containers are read-only except `/tmp`. ChromaDB's default `./chroma_data` path resolves to the read-only container filesystem. Setting `CHROMA_PATH=/mnt/efs/chroma_data` via ECS task env var points it at the EFS mount.

---

### Step 3 — Terraform: Networking ✅
**What:** VPC, subnets, internet gateway, NAT gateway, route tables, security groups.

**Files:** `infra/vpc.tf`, `infra/security_groups.tf`

**Resources created:**
| Resource | Purpose |
|---|---|
| VPC (`10.0.0.0/16`) | Isolated network for all resources |
| 2× Public subnets | ALB lives here (internet-facing) |
| 2× Private subnets | ECS tasks, RDS, EFS (no direct internet) |
| Internet Gateway | Public subnets → internet |
| NAT Gateway | Private subnets → internet (for Bedrock, DuckDuckGo) |
| Route tables | Wire IGW and NAT to correct subnets |
| SG: `ci-alb-sg` | Allow 443 inbound; forward 8501 to ECS |
| SG: `ci-ecs-sg` | Allow 8501 from ALB; all outbound |
| SG: `ci-rds-sg` | Allow 5432 from ECS only |
| SG: `ci-efs-sg` | Allow 2049 (NFS) from ECS only |

**Validate:**
```bash
cd infra
terraform init
terraform plan   # should show ~15 resources, no errors
```

---

### Step 4 — Terraform: Data Layer ✅
**What:** RDS PostgreSQL and EFS for ChromaDB.

**Files:** `infra/rds.tf`, `infra/efs.tf`

**Resources created:**
| Resource | Config |
|---|---|
| RDS PostgreSQL 15 | `db.t3.micro`, private subnet, no public access |
| DB subnet group | Spans both private subnets (RDS requirement) |
| EFS filesystem | General Purpose, encrypted at rest |
| EFS mount targets | One per AZ (so both private subnets can mount) |
| EFS access point | Scoped to `/chroma_data` path with correct permissions |

**After apply:**
```bash
# Get the RDS endpoint from Terraform output
terraform output rds_endpoint

# Apply the database schema
psql postgresql://postgres:<password>@<rds-endpoint>:5432/competitive_intelligence \
  -f ../app/db/schema.sql
```

---

### Step 5 — Terraform: Container Infrastructure ✅
**What:** ECR, IAM roles, ALB, ECS cluster + task definitions + service.

**Files:** `infra/ecr.tf`, `infra/iam.tf`, `infra/alb.tf`, `infra/ecs.tf`

**Resources created:**
| Resource | Purpose |
|---|---|
| ECR repository | Stores the Docker image |
| ECS Task Execution Role | Allows ECS to pull from ECR, write to CloudWatch |
| ECS Task Role | Allows app code to call `bedrock:InvokeModel` |
| EventBridge Role | Allows EventBridge to trigger ECS RunTask |
| ALB | Internet-facing load balancer in public subnets |
| Target group | Routes to ECS tasks on port 8501 |
| ALB listener (HTTP) | Redirects to HTTPS |
| ALB listener (HTTPS) | Forwards to target group (needs ACM cert) |
| ECS cluster | Fargate launch type |
| Task definition: `ci-dashboard` | 0.5 vCPU, 1GB, Streamlit command, EFS mount |
| Task definition: `ci-agent` | 1 vCPU, 2GB, `python scripts/run_multiple.py`, EFS mount |
| ECS service: `ci-dashboard` | desired_count=1, wired to ALB target group |

**After apply:**
```bash
# Build and push the Docker image
terraform output ecr_repository_url   # get the ECR URL

aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ecr-url>

docker build -t <ecr-url>:latest .
docker push <ecr-url>:latest

# Force the ECS service to pull the new image
aws ecs update-service \
  --cluster ci-prod \
  --service ci-dashboard \
  --force-new-deployment
```

**Verify:** Hit the ALB DNS name — Streamlit dashboard should load.

---

### Step 6 — Terraform: Scheduling + Observability ✅
**What:** EventBridge schedule for the agent, CloudWatch log groups.

**Files:** `infra/eventbridge.tf`, `infra/cloudwatch.tf`

**Resources created:**
| Resource | Purpose |
|---|---|
| CloudWatch log group `/ecs/ci-dashboard` | Dashboard container logs (30-day retention) |
| CloudWatch log group `/ecs/ci-agent` | Agent container logs (30-day retention) |
| EventBridge rule `ci-agent-weekly` | Cron: every Monday 9am UTC |
| EventBridge target | Runs `ci-agent` ECS task when rule fires |

**Test the agent manually before relying on the schedule:**
```bash
aws ecs run-task \
  --cluster ci-prod \
  --task-definition ci-agent \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"

# Tail the logs
aws logs tail /ecs/ci-agent --follow
```

---

### Step 7 — CI/CD Pipeline (GitHub Actions) ✅
**What:** Automated build → push → deploy on every push to `main`.

**Files:** `.github/workflows/deploy.yml`, `infra/github_actions.tf`

**Pipeline stages:**
```
push to main
     │
     ▼
[checkout code]
     │
     ▼
[configure AWS credentials]      ← OIDC: no static keys in GitHub
     │
     ▼
[docker build + push to ECR]     ← tagged sha-<git-sha> + :latest
     │
     ▼
[terraform init + plan]          ← TF_VAR_image_tag=sha-<git-sha>
     │
     ▼
[terraform apply -auto-approve]  ← new task definition revision → ECS rolling deploy
```

**GitHub secrets required:**
| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | ARN from `terraform output github_actions_role_arn` |
| `TF_VAR_DB_PASSWORD` | RDS master password |

**Bootstrap — one-time local setup before CI/CD works:**
```bash
# 1. Set your DB password for the first apply
export TF_VAR_db_password="your-strong-password"

# 2. Fill in terraform.tfvars (copy from example and edit)
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Set: github_repo = "your-username/competitive-intelligence-migrate"

# 3. (Optional but recommended) Create S3 backend for shared state
aws s3 mb s3://ci-terraform-state-$(aws sts get-caller-identity --query Account --output text)
aws dynamodb create-table \
  --table-name ci-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
# Then uncomment the backend block in infra/main.tf

# 4. First apply — runs locally with your personal AWS credentials
cd infra
terraform init
terraform apply

# 5. Copy the role ARN from the output
terraform output github_actions_role_arn
# → Add as GitHub secret: AWS_ROLE_ARN

# 6. Add TF_VAR_DB_PASSWORD as a GitHub secret
# GitHub repo → Settings → Secrets and variables → Actions → New secret

# All future deployments run automatically via GitHub Actions on push to main
```

---

### Step 8 — First Deployment & Verification
**What:** Run the full pipeline end-to-end entirely from GitHub — no local tooling needed.

#### Phase 1 — Bootstrap (one-time, ~5 minutes)

**GitHub secrets to add first** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `AWS_BOOTSTRAP_KEY_ID` | Access key ID for an IAM user with AdministratorAccess |
| `AWS_BOOTSTRAP_SECRET_KEY` | Secret key for the same IAM user |
| `TF_VAR_DB_PASSWORD` | A strong password for RDS (e.g. `P@ssw0rd!Secure99`) |

Then go to **Actions → Bootstrap (run once) → Run workflow** and click **Run workflow**.

When it finishes, open the job summary — it prints the `AWS_ROLE_ARN` value. Add it as a fourth secret:

| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | Printed in bootstrap job summary |

You can now **delete** `AWS_BOOTSTRAP_KEY_ID` and `AWS_BOOTSTRAP_SECRET_KEY` — they are never needed again.

---

#### Phase 2 — Full Deploy (every push to main)

Push any change to `main` (or trigger `deploy.yml` manually) to run the full pipeline:

```
build image → push to ECR → terraform apply → ECS rolling deploy
```

**After the first deploy completes:**
- [ ] ECS service reaches `RUNNING` (ECS console → Services)
- [ ] ALB health check passes (Target Groups → Health status = healthy)
- [ ] Dashboard loads at the ALB DNS name (from `terraform output alb_dns_name`)

---

#### Phase 3 — Seed the database

The RDS database exists but has no schema and no data yet. Run the agent once to populate it.

**Apply schema** — run this from AWS CloudShell (browser-based terminal in AWS console):
```bash
# Install psql
sudo dnf install -y postgresql15

# Apply schema (get DATABASE_URL from SSM Parameter Store)
DB_URL=$(aws ssm get-parameter \
  --name "/ci/prod/database-url" \
  --with-decryption \
  --query Parameter.Value \
  --output text)

# Download schema from your repo and apply
curl -sO https://raw.githubusercontent.com/<your-repo>/main/app/db/schema.sql
psql "$DB_URL" -f schema.sql
```

**Run the agent manually** — trigger a one-off ECS task from the AWS console:
```
ECS → Clusters → ci-prod → Tasks → Run new task
  Launch type: FARGATE
  Task definition: ci-prod-agent
  Cluster: ci-prod
  Subnet: either private subnet
  Security group: ci-prod-ecs-sg
```

Or via AWS CLI from CloudShell:
```bash
aws ecs run-task \
  --cluster ci-prod \
  --task-definition ci-prod-agent \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[$(aws ec2 describe-subnets \
      --filters Name=tag:Name,Values='ci-prod-private-1' \
      --query 'Subnets[0].SubnetId' --output text)],
    securityGroups=[$(aws ec2 describe-security-groups \
      --filters Name=tag:Name,Values='ci-prod-ecs-sg' \
      --query 'SecurityGroups[0].GroupId' --output text)],
    assignPublicIp=DISABLED
  }"
```

**Tail agent logs** (CloudShell):
```bash
aws logs tail /ecs/ci-prod/agent --follow
```

---

#### Final Verification Checklist
- [ ] Bootstrap job summary shows role ARN
- [ ] `deploy.yml` completes green on push to main
- [ ] ECS service is RUNNING (1/1 tasks healthy)
- [ ] ALB DNS name loads the Streamlit dashboard
- [ ] Agent task runs and logs show signals being saved
- [ ] Dashboard displays competitor signals after agent run
- [ ] Chat sidebar answers questions using RAG context
- [ ] CloudWatch alarms are in OK state

---

## Cost Summary

| Service | Monthly |
|---|---|
| ECS Fargate — dashboard (0.25 vCPU, always-on) | ~$10 |
| ECS Fargate — agent (0.5 vCPU, ~20 min/week) | ~$0.50 |
| RDS db.t3.micro | ~$15 |
| EFS (~50 MB) | ~$0.02 |
| ALB | ~$16 |
| NAT Gateway | ~$32 |
| ECR (~2 GB image) | ~$0.20 |
| Bedrock (Claude Sonnet) | ~$5–20 |
| **Total** | **~$79–94/mo** |

> To reduce NAT Gateway cost (~$32/mo): assign `FARGATE` tasks a public IP and remove the NAT Gateway. Works for dev/staging; for production keep NAT to keep ECS tasks in private subnets.

---

## Local Development

```bash
# Clone and set up
git clone <this-repo>
cd COMPETITIVE-INTELLIGENCE-MIGRATE
cp .env.example .env        # fill in local values

# Build and run locally
docker build -t ci-local .
docker run -p 8501:8501 --env-file .env ci-local

# Open http://localhost:8501
```
