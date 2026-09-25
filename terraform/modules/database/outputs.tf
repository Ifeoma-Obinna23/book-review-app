# Outputs for the database module.
#
# Never output the password itself, not even marked sensitive — the app tier
# reads credentials from Secrets Manager at runtime via IAM, not via
# Terraform state.

output "db_endpoint" {
  description = "Primary RDS endpoint (host:port) for the Application Tier to connect to for reads and writes."
  value       = aws_db_instance.primary.endpoint
}

output "db_replica_endpoint" {
  description = "Read replica endpoint (host:port) for read-scaled queries. Omit usage of this in the app tier if you are not doing read/write splitting yet."
  value       = aws_db_instance.read_replica.endpoint
}

output "db_port" {
  description = "MySQL port (3306) exposed by the primary instance."
  value       = aws_db_instance.primary.port
}

output "db_name" {
  description = "Initial database name created inside MySQL."
  value       = aws_db_instance.primary.db_name
}

output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN holding the master credentials. The app tier's IAM role is granted read access to this — it is a pointer, not a credential, so it is safe to output."
  value       = aws_secretsmanager_secret.db_master.arn
}
