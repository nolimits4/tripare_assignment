output "vpc_id" {
  description = "ID of the dev VPC."
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
