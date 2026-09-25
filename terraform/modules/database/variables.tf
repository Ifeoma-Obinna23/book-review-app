# Inputs for the database module.
#
# There is deliberately NO password variable. The master password is generated
# inside this module with random_password and stored in a secrets store.

variable "private_db_subnet_ids" {
  description = "Private database subnet IDs (one per AZ) for the DB subnet group."
  type        = list(string)

  validation {
    condition     = length(var.private_db_subnet_ids) >= 2
    error_message = "Provide at least 2 private DB subnets across 2 AZs for Multi-AZ RDS."
  }
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

variable "db_secret_name" {
  description = "Name of the Secrets Manager secret holding the master credentials. Must match var.db_secret_name passed to the compute module, since the app tier's IAM policy (secrets_manager_arn_pattern) is scoped to this exact name -- a mismatch here silently breaks the app tier's ability to read its own database password."
  type        = string
}

# --- Engine / sizing / backup settings ---

variable "db_name" {
  description = "Initial database name created inside the MySQL instance."
  type        = string
  default     = "bookreview"
}

variable "db_username" {
  description = "Master username for the RDS instance (not the password — that is generated)."
  type        = string
  default     = "admin"
}

variable "engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "RDS instance class for the primary."
  type        = string
  default     = "db.t3.medium"
}

variable "replica_instance_class" {
  description = "RDS instance class for the read replica."
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Storage (GB) for the primary instance."
  type        = number
  default     = 20
}

variable "backup_retention_days" {
  description = "Number of days automated backups are retained."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection. Should be true for any non-dev environment."
  type        = bool
  default     = true
}

variable "multi_az" {
  description = "Enable Multi-AZ failover for the primary instance."
  type        = bool
  default     = true
}
