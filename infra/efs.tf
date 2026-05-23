# ─── EFS File System ──────────────────────────────────────────────────────────
# Persistent storage for ChromaDB (./chroma_data).
# ECS containers are ephemeral — without EFS, the vector store is lost on
# every task restart. Both the dashboard and agent tasks mount this volume
# so embeddings written by the agent are immediately available to the dashboard.

resource "aws_efs_file_system" "chroma" {
  creation_token   = "${var.project_name}-${var.environment}-chroma"
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"   # scales with usage, no provisioning needed
  encrypted        = true

  # Move files to Infrequent Access storage after 7 days of no reads.
  # ChromaDB's sqlite3 + index files are small (~50 MB) — this saves cost
  # if the agent runs infrequently.
  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS"
  }

  tags = { Name = "${var.project_name}-${var.environment}-chroma-efs" }
}

# ─── Mount Targets ────────────────────────────────────────────────────────────
# One mount target per private subnet (one per AZ).
# An ECS task in either AZ can reach the same EFS filesystem via its local
# mount target — avoids cross-AZ data transfer costs.

resource "aws_efs_mount_target" "chroma" {
  count = length(var.availability_zones)

  file_system_id  = aws_efs_file_system.chroma.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# ─── Access Point ─────────────────────────────────────────────────────────────
# Scopes the ECS containers to /chroma_data within the filesystem.
# POSIX uid/gid 1000 matches the default non-root user in python:3.11-slim,
# so the container can write without running as root.

resource "aws_efs_access_point" "chroma" {
  file_system_id = aws_efs_file_system.chroma.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/chroma_data"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-chroma-ap" }
}
