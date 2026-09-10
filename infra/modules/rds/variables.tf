variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. hotelapp-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group. At least two AZs are required."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups permitted to reach the database. Only the ECS task security group belongs here."
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class, sized per environment."
  type        = string
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GiB. Set to 0 to disable."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "hotelapp"
}

variable "db_username" {
  description = "Master username."
  type        = string
  default     = "hotelapp_admin"
}

variable "db_port" {
  description = "Port the database listens on."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Run a standby in a second AZ. Enabled in prod."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups to keep."
  type        = number

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days so automated backups stay enabled."
  }
}

variable "backup_window" {
  description = "Daily backup window in UTC."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC."
  type        = string
  default     = "sun:04:30-sun:05:30"
}

variable "deletion_protection" {
  description = "Block accidental deletion of the instance. Enabled in prod."
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True in dev, false in prod."
  type        = bool
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds. 0 disables it."
  type        = number
  default     = 0
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of during the maintenance window."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
