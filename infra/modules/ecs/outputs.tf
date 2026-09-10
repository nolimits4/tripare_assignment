output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster. The scheduled backup task reuses it."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_security_group_id" {
  description = "Security group attached to the Fargate tasks. RDS grants access to this group only."
  value       = aws_security_group.tasks.id
}

output "alb_security_group_id" {
  description = "Security group attached to the load balancer."
  value       = aws_security_group.alb.id
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "task_definition_arn" {
  description = "ARN of the active task definition revision."
  value       = aws_ecs_task_definition.this.arn
}
