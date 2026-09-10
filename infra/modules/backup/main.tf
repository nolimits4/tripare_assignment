terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  bucket_name    = "${var.name_prefix}-db-backups-${data.aws_caller_identity.current.account_id}"
  container_name = "${var.name_prefix}-db-backup"
}

# --- Destination bucket ------------------------------------------------------

resource "aws_s3_bucket" "backups" {
  bucket = local.bucket_name

  # Only ever true in dev. In prod an accidental `terraform destroy` must not
  # be able to take the backup history with it.
  force_destroy = var.force_destroy_bucket

  tags = merge(var.tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Versioning protects against a bad dump overwriting a good one at the same
# key, and against deletion by a compromised task role.
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  depends_on = [aws_s3_bucket_versioning.backups]

  rule {
    id     = "dump-lifecycle"
    status = "Enabled"

    filter {
      prefix = "dumps/"
    }

    dynamic "transition" {
      for_each = var.transition_to_ia_days > 0 ? [1] : []
      content {
        days          = var.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.transition_to_glacier_days > 0 ? [1] : []
      content {
        days          = var.transition_to_glacier_days
        storage_class = "GLACIER_IR"
      }
    }

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }
}

# --- Logging -----------------------------------------------------------------

resource "aws_cloudwatch_log_group" "backup" {
  name              = "/ecs/${var.name_prefix}-db-backup"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# --- IAM ---------------------------------------------------------------------

data "aws_iam_policy_document" "task_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-db-backup-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_db_secret" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "execution_read_secret" {
  name   = "${var.name_prefix}-db-backup-read-secret"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-db-backup-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json

  tags = var.tags
}

# Write-only, scoped to the dumps/ prefix of this one bucket. The task can
# create backups but cannot read or delete existing ones, so a compromised
# task cannot exfiltrate or destroy the backup history.
data "aws_iam_policy_document" "task_s3_write" {
  statement {
    sid       = "PutDumps"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.backups.arn}/dumps/*"]
  }

  statement {
    sid       = "ListForMultipart"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["dumps/*"]
    }
  }
}

resource "aws_iam_role_policy" "task_s3_write" {
  name   = "${var.name_prefix}-db-backup-s3-write"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_s3_write.json
}

# --- Task definition ---------------------------------------------------------

locals {
  # pg_dump straight into S3. --format=custom is compressed and restorable
  # selectively; piping through `aws s3 cp -` avoids needing local disk large
  # enough to stage the dump.
  backup_command = <<-EOT
    set -euo pipefail
    echo "Installing the AWS CLI..."
    apk add --no-cache aws-cli >/dev/null
    TS="$(date -u +%Y%m%dT%H%M%SZ)"
    KEY="dumps/${var.db_name}/$${TS}/${var.db_name}_$${TS}.dump"
    echo "Dumping ${var.db_name} to s3://${local.bucket_name}/$${KEY}"
    PGPASSWORD="$${DB_PASSWORD}" pg_dump \
      --host="${var.db_host}" \
      --port=${var.db_port} \
      --username="$${DB_USERNAME}" \
      --dbname="${var.db_name}" \
      --format=custom \
      --no-owner \
      --no-privileges \
      | aws s3 cp - "s3://${local.bucket_name}/$${KEY}" \
          --expected-size 5368709120
    echo "Backup complete: $${KEY}"
  EOT
}

resource "aws_ecs_task_definition" "backup" {
  family                   = "${var.name_prefix}-db-backup"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.backup_image
      essential = true

      entryPoint = ["/bin/sh", "-c"]
      command    = [local.backup_command]

      secrets = [
        {
          name      = "DB_USERNAME"
          valueFrom = "${var.db_secret_arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backup.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "backup"
        }
      }
    }
  ])

  tags = var.tags
}

# --- Schedule ----------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    # Prevents this role being usable by any other account's scheduler.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.name_prefix}-db-backup-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "scheduler_run_task" {
  statement {
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    # Built by hand rather than using arn_without_revision so the permission
    # covers every future revision, not just the one current at apply time.
    resources = [
      format(
        "arn:aws:ecs:%s:%s:task-definition/%s:*",
        data.aws_region.current.name,
        data.aws_caller_identity.current.account_id,
        aws_ecs_task_definition.backup.family,
      )
    ]

    condition {
      test     = "ArnLike"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }

  # RunTask has to hand the task its roles.
  statement {
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.task_execution.arn,
      aws_iam_role.task.arn,
    ]
  }
}

resource "aws_iam_role_policy" "scheduler_run_task" {
  name   = "${var.name_prefix}-db-backup-run-task"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_run_task.json
}

resource "aws_scheduler_schedule" "backup" {
  name       = "${var.name_prefix}-db-backup"
  group_name = "default"
  state      = var.schedule_enabled ? "ENABLED" : "DISABLED"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 15
  }

  target {
    arn      = var.ecs_cluster_arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.backup.arn
      launch_type         = "FARGATE"
      task_count          = 1
      propagate_tags      = "TASK_DEFINITION"

      network_configuration {
        subnets          = var.private_subnet_ids
        security_groups  = var.security_group_ids
        assign_public_ip = false
      }
    }

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# --- Failure alarm -----------------------------------------------------------

# A backup job that silently stops running is indistinguishable from one that
# is working until the day it is needed. This alarm fires when no successful
# dump has been logged within a window covering two scheduled runs.
resource "aws_cloudwatch_log_metric_filter" "backup_success" {
  count = var.alarm_on_failure ? 1 : 0

  name           = "${var.name_prefix}-db-backup-success"
  log_group_name = aws_cloudwatch_log_group.backup.name
  pattern        = "\"Backup complete\""

  metric_transformation {
    name          = "DatabaseBackupSuccess"
    namespace     = "${var.name_prefix}/Backups"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "backup_missing" {
  count = var.alarm_on_failure ? 1 : 0

  alarm_name        = "${var.name_prefix}-db-backup-missing"
  alarm_description = "No successful database backup completed in the expected window."

  namespace   = "${var.name_prefix}/Backups"
  metric_name = aws_cloudwatch_log_metric_filter.backup_success[0].metric_transformation[0].name
  statistic   = "Sum"

  # Two scheduled intervals plus the flexible window, so a single retried run
  # does not trip it.
  period              = 32400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  tags = var.tags
}
