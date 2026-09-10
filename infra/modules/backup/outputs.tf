output "bucket_name" {
  description = "Name of the S3 bucket holding the dumps."
  value       = aws_s3_bucket.backups.bucket
}

output "bucket_arn" {
  description = "ARN of the backup bucket."
  value       = aws_s3_bucket.backups.arn
}

output "task_definition_arn" {
  description = "ARN of the backup task definition."
  value       = aws_ecs_task_definition.backup.arn
}

output "schedule_name" {
  description = "Name of the EventBridge schedule."
  value       = aws_scheduler_schedule.backup.name
}

output "schedule_expression" {
  description = "Cadence the backup runs at."
  value       = aws_scheduler_schedule.backup.schedule_expression
}

output "log_group_name" {
  description = "CloudWatch log group the backup task writes to."
  value       = aws_cloudwatch_log_group.backup.name
}

output "alarm_name" {
  description = "Name of the missing-backup alarm, if enabled."
  value       = var.alarm_on_failure ? aws_cloudwatch_metric_alarm.backup_missing[0].alarm_name : null
}
