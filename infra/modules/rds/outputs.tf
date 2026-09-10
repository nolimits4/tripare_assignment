output "endpoint" {
  description = "Connection endpoint including the port."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the database instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "Security group attached to the database."
  value       = aws_security_group.this.id
}

output "secret_arn" {
  description = "Secrets Manager ARN holding the master credentials."
  value       = aws_secretsmanager_secret.db.arn
}

output "instance_identifier" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.this.identifier
}
