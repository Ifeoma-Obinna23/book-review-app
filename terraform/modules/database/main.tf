#############################################
# 1. Master password + JWT secret — never in a .tf/.tfvars file
#############################################

resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Bundled into the same secret as the DB credentials, per the existing
# contract: one db_secret_name, one secrets_manager_arn_pattern, one IAM
# read permission for the app tier. JWT_SECRET is high-entropy and does not
# need special characters that could complicate shell/env-var handling in
# the boot script, so it is restricted to alphanumerics.
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "db_master" {
  name        = var.db_secret_name
  description = "DB credentials and JWT secret for the ${var.project_name} app tier, read by its IAM role at boot"

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Tier        = "database"
  })
}

# Keys must exactly match what the compute module's boot script reads:
# DB_HOST, DB_NAME, DB_USER, DB_PASS, JWT_SECRET. DB_HOST uses .address
# (bare hostname), not .endpoint (which appends ":3306") -- the port is
# fixed elsewhere per CLAUDE.md and should not be string-concatenated here.
resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    DB_HOST    = aws_db_instance.primary.address
    DB_NAME    = var.db_name
    DB_USER    = var.db_username
    DB_PASS    = random_password.db_master.result
    JWT_SECRET = random_password.jwt_secret.result
  })
}

#############################################
# 2. DB subnet group — private DB subnets only, 2+ AZs
#############################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_db_subnet_ids

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Tier        = "database"
  })
}

# NOTE: the DB security group itself (inbound 3306 from the app tier SG only)
# is created in the security module and passed in as
# var.database_security_group_id. This module does not create or modify
# security group rules — it only attaches the SG to the RDS instances.

#############################################
# 3. Primary RDS instance — Multi-AZ, encrypted, private
#############################################

resource "aws_db_instance" "primary" {
  identifier     = "${var.project_name}-${var.environment}-mysql-primary"
  engine         = "mysql"
  engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.database_security_group_id]
  publicly_accessible    = false

  multi_az = var.multi_az

  backup_retention_period   = var.backup_retention_days
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.environment == "dev" ? true : false
  final_snapshot_identifier = var.environment == "dev" ? null : "${var.project_name}-${var.environment}-final-snapshot"

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Tier        = "database"
    Role        = "primary"
  })

  lifecycle {
    ignore_changes = [password] # rotate via Secrets Manager, not via re-apply
  }
}

#############################################
# 4. Read replica — read scaling, NOT a failover target
#############################################

resource "aws_db_instance" "read_replica" {
  identifier          = "${var.project_name}-${var.environment}-mysql-replica"
  replicate_source_db = aws_db_instance.primary.identifier

  instance_class    = var.replica_instance_class
  storage_encrypted = true

  publicly_accessible    = false
  vpc_security_group_ids = [var.database_security_group_id]

  # multi_az is intentionally omitted here. Multi-AZ is a failover property
  # of the primary; the replica is a separate read endpoint for scaling
  # read traffic, not a second failover copy.

  skip_final_snapshot = true

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Tier        = "database"
    Role        = "read-replica"
  })
}
