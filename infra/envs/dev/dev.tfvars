aws_region  = "ap-south-1"
project     = "hotelapp"
environment = "dev"

tags = {
  Owner      = "platform-team"
  CostCenter = "engineering"
}

# Network: one NAT gateway shared across AZs keeps the dev bill small.
vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

# Compute: smallest usable Fargate task, single replica.
container_image         = "nginx:alpine"
container_port          = 80
task_cpu                = 256
task_memory             = 512
desired_count           = 1
log_retention_days      = 7
alb_deletion_protection = false

# Database: small instance, short retention, destroyable.
db_engine_version               = "16.4"
db_instance_class               = "db.t4g.micro"
db_allocated_storage            = 20
db_max_allocated_storage        = 50
db_name                         = "hotelapp"
db_username                     = "hotelapp_admin"
db_multi_az                     = false
db_backup_retention_period      = 1
db_deletion_protection          = false
db_skip_final_snapshot          = true
db_performance_insights_enabled = false
db_monitoring_interval          = 0
db_apply_immediately            = true
