# Scheduled logical backups.
#
# RDS automated backups (configured in the rds module) already cover
# point-in-time recovery. This adds pg_dump archives on top, which snapshots
# cannot replace: a dump is portable across major versions and can be restored
# into a different engine, a different account, or a laptop.

# The security group is created here rather than inside the backup module.
# The RDS security group must reference it, and the backup module consumes the
# RDS secret ARN, so defining it in the module would create a cycle between
# the two.
resource "aws_security_group" "backup_task" {
  name        = "${local.name_prefix}-db-backup-sg"
  description = "Scheduled database backup task."
  vpc_id      = module.network.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-backup-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Outbound only: the task needs S3, Secrets Manager and the image registry.
# Reaching the database is granted by the RDS security group, not here.
resource "aws_vpc_security_group_egress_rule" "backup_task_all" {
  security_group_id = aws_security_group.backup_task.id
  description       = "Outbound to S3, Secrets Manager and the registry via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = local.common_tags
}

module "backup" {
  source = "../../modules/backup"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = [aws_security_group.backup_task.id]
  ecs_cluster_arn    = module.ecs.cluster_arn

  db_secret_arn = module.rds.secret_arn
  db_host       = module.rds.address
  db_name       = module.rds.db_name
  db_port       = module.rds.port

  schedule_expression = var.backup_schedule_expression
  schedule_enabled    = var.backup_schedule_enabled

  retention_days             = var.backup_retention_days
  transition_to_ia_days      = var.backup_transition_to_ia_days
  transition_to_glacier_days = var.backup_transition_to_glacier_days
  log_retention_days         = var.log_retention_days

  alarm_on_failure     = var.backup_alarm_on_failure
  force_destroy_bucket = var.backup_force_destroy_bucket

  tags = local.common_tags
}
