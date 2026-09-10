variable "aws_region" {
  description = "AWS region for the prod environment."
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
  default     = "prod"
}

variable "tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

# --- Network -----------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the prod VPC. Kept distinct from dev so the two can be peered later."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Availability zones to spread subnets across."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "Prod runs one NAT gateway per AZ so a single AZ failure cannot cut egress."
  type        = bool
  default     = false
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
  default     = 1024
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Number of running tasks."
  type        = number
  default     = 3
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention."
  type        = number
  default     = 90
}

variable "alb_deletion_protection" {
  description = "Deletion protection on the load balancer."
  type        = bool
  default     = true
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
  default     = "db.m6g.large"
}

variable "db_allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 500
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
  default     = true
}

variable "db_backup_retention_period" {
  description = "Automated backup retention in days."
  type        = number
  default     = 30
}

variable "db_deletion_protection" {
  description = "Deletion protection on the database."
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
  default     = false
}

variable "db_performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = true
}

variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds. 0 disables it."
  type        = number
  default     = 60
}

variable "db_apply_immediately" {
  description = "Apply database changes immediately rather than in the maintenance window."
  type        = bool
  default     = false
}
