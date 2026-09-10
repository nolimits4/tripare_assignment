aws_region  = "ap-south-1"
project     = "hotelapp"
environment = "prod"

tags = {
  Owner      = "platform-team"
  CostCenter = "engineering"
  Compliance = "pci-scope"
}

# Network: three AZs and one NAT gateway per AZ, so losing an AZ does not cut
# egress for the surviving tasks.
vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = false

# Compute: larger task, three replicas across AZs, ALB protected from deletion.
container_image         = "nginx:alpine"
container_port          = 80
task_cpu                = 1024
task_memory             = 2048
desired_count           = 3
log_retention_days      = 90
alb_deletion_protection = true

# Database: larger instance, Multi-AZ, 30 day retention, deletion protected and
# a final snapshot is always taken.
db_engine_version               = "16.4"
db_instance_class               = "db.m6g.large"
db_allocated_storage            = 100
db_max_allocated_storage        = 500
db_name                         = "hotelapp"
db_username                     = "hotelapp_admin"
db_multi_az                     = true
db_backup_retention_period      = 30
db_deletion_protection          = true
db_skip_final_snapshot          = false
db_performance_insights_enabled = true
db_monitoring_interval          = 60
db_apply_immediately            = false
