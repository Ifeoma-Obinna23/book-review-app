# Inputs for the database module.
# Kept minimal on purpose — engine version, instance class, storage sizing and
# backup settings get added when the aws_db_instance is actually written.
#
# There is deliberately NO password variable. The master password is generated
# inside this module with random_password and stored in a secrets store.

variable "private_db_subnet_ids" {
  description = "Private database subnet IDs (one per AZ) for the DB subnet group."
  type        = list(string)
}

variable "database_security_group_id" {
  description = "Security group ID for RDS, from the security module. Allows 3306 from the app tier only."
  type        = string
}

variable "project_name" {
  description = "Project identifier used for resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)."
  type        = string
}

variable "tags" {
  description = "Additional tags merged onto every resource in this module."
  type        = map(string)
  default     = {}
}
