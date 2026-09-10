variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. hotelapp-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster and load balancer live in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the internet-facing ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks."
  type        = list(string)
}

variable "container_image" {
  description = "Container image for the application task."
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, 2048, 4096)."
  type        = number
}

variable "task_memory" {
  description = "Fargate task memory in MiB. Must be valid for the chosen CPU."
  type        = number
}

variable "desired_count" {
  description = "Number of tasks the service keeps running."
  type        = number
}

variable "health_check_path" {
  description = "Path the ALB target group health check requests."
  type        = string
  default     = "/"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the task log group."
  type        = number
  default     = 7
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion. Enabled in prod."
  type        = bool
  default     = false
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding the database credentials, injected into the task."
  type        = string
  default     = null
}

variable "db_endpoint" {
  description = "RDS endpoint passed to the container as an environment variable."
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Database name passed to the container as an environment variable."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
