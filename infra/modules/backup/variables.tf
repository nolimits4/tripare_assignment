variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. hotelapp-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC the backup task runs in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets the backup task runs in. Needs a NAT route to reach S3 and Secrets Manager."
  type        = list(string)
}

variable "security_group_ids" {
  description = <<-EOT
    Security groups for the backup task. Created in the environment root rather
    than here: the RDS security group must allow this group, and this module
    consumes the RDS secret ARN, so creating it here would form a dependency
    cycle between the two modules.
  EOT
  type        = list(string)
}

variable "ecs_cluster_arn" {
  description = "ECS cluster the scheduled backup task runs on. Reuses the application cluster."
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding the database credentials."
  type        = string
}

variable "db_host" {
  description = "Database hostname to dump from."
  type        = string
}

variable "db_name" {
  description = "Database name to dump."
  type        = string
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression controlling how often the dump runs."
  type        = string
  default     = "rate(4 hours)"
}

variable "schedule_enabled" {
  description = "Whether the schedule is active. Disable in dev to avoid needless spend."
  type        = bool
  default     = true
}

variable "backup_image" {
  description = <<-EOT
    Image used by the backup task. It needs both pg_dump and the AWS CLI.

    The default is the stock Postgres image with the AWS CLI installed at
    runtime, which keeps this repository self-contained. A real deployment
    should build a small purpose-made image, push it to ECR and pin it by
    digest, so the task does not depend on a package mirror at run time.
  EOT
  type        = string
  default     = "public.ecr.aws/docker/library/postgres:16-alpine"
}

variable "task_cpu" {
  description = "CPU units for the backup task."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Memory in MiB for the backup task."
  type        = number
  default     = 1024
}

variable "retention_days" {
  description = "Days before a dump is deleted from S3."
  type        = number
}

variable "transition_to_ia_days" {
  description = "Days before a dump moves to Standard-IA. Set to 0 to disable."
  type        = number
  default     = 30
}

variable "transition_to_glacier_days" {
  description = "Days before a dump moves to Glacier Instant Retrieval. Set to 0 to disable."
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the backup task."
  type        = number
  default     = 30
}

variable "alarm_on_failure" {
  description = "Raise a CloudWatch alarm when a scheduled backup fails."
  type        = bool
  default     = true
}

variable "force_destroy_bucket" {
  description = "Allow Terraform to delete a non-empty backup bucket. True in dev only."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
