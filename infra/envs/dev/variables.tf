variable "aws_region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name, used as the first half of every resource name."
  type        = string
  default     = "hotelapp"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

# --- Network -----------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "az_count" {
  description = "Availability zones to spread subnets across."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Dev shares one NAT gateway to keep costs down."
  type        = bool
  default     = true
}

# --- ECS ---------------------------------------------------------------------

variable "container_image" {
  description = "Application container image."
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of running tasks."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention."
  type        = number
  default     = 7
}

variable "alb_deletion_protection" {
  description = "Deletion protection on the load balancer."
  type        = bool
  default     = false
}

# --- RDS ---------------------------------------------------------------------

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 50
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "hotelapp"
}

variable "db_username" {
  description = "Master username."
  type        = string
  default     = "hotelapp_admin"
}

variable "db_multi_az" {
  description = "Multi-AZ standby."
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Automated backup retention in days."
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "Deletion protection on the database."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
  default     = true
}

variable "db_performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = false
}

variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds. 0 disables it."
  type        = number
  default     = 0
}

variable "db_apply_immediately" {
  description = "Apply database changes immediately rather than in the maintenance window."
  type        = bool
  default     = true
}

# --- Scheduled backups -------------------------------------------------------

variable "backup_schedule_expression" {
  description = "How often the pg_dump task runs."
  type        = string
  default     = "rate(4 hours)"
}

variable "backup_schedule_enabled" {
  description = "Whether the schedule is active. Off in dev by default, since RDS automated backups already cover it and Fargate runs cost money."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days before a dump is deleted from S3."
  type        = number
  default     = 7
}

variable "backup_transition_to_ia_days" {
  description = "Days before a dump moves to Standard-IA. 0 disables the transition."
  type        = number
  default     = 0
}

variable "backup_transition_to_glacier_days" {
  description = "Days before a dump moves to Glacier Instant Retrieval. 0 disables the transition."
  type        = number
  default     = 0
}

variable "backup_alarm_on_failure" {
  description = "Alarm when no successful backup completes in the expected window."
  type        = bool
  default     = false
}

variable "backup_force_destroy_bucket" {
  description = "Let Terraform delete a non-empty backup bucket. Acceptable in dev only."
  type        = bool
  default     = true
}
