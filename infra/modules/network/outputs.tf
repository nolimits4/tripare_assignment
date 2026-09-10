output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, used by the ALB."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, used by ECS tasks and RDS."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "Availability zones the subnets were placed in."
  value       = local.azs
}
