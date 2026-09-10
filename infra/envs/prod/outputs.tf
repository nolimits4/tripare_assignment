output "vpc_id" {
  description = "ID of the prod VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets hosting the load balancer."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnets hosting the tasks and the database."
  value       = module.network.private_subnet_ids
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer."
  value       = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = module.ecs.cluster_name
}

output "rds_endpoint" {
  description = "Private endpoint of the database."
  value       = module.rds.endpoint
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN holding the database credentials."
  value       = module.rds.secret_arn
}

output "backup_bucket_name" {
  description = "S3 bucket holding the scheduled pg_dump archives."
  value       = module.backup.bucket_name
}

output "backup_schedule" {
  description = "Cadence of the scheduled backup task."
  value       = module.backup.schedule_expression
}

output "backup_alarm_name" {
  description = "CloudWatch alarm that fires when a backup window passes without a successful dump."
  value       = module.backup.alarm_name
}
