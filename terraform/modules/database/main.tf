# Database module — scaffold only, no resources yet.
#
# Purpose
#   Provisions the managed MySQL instance (RDS) for the Book Review App and
#   the machinery that keeps its credentials out of source control.
#
# Security boundaries this module must enforce (CLAUDE.md sections 2, 3, 4)
#
#   Placement
#     DB subnet group spans private-db-subnet-az1 and private-db-subnet-az2.
#     multi_az = true, so at least 2 Availability Zones.
#
#   Exposure
#     publicly_accessible = false. No public IP, and the db subnets have no
#     route to an Internet Gateway.
#     Inbound 3306 is allowed ONLY from the app tier security group — no CIDR
#     source, no 0.0.0.0/0, nothing from the web tier or either ALB.
#
#   Credentials (CLAUDE.md section 4 — non-negotiable)
#     The master password is generated with random_password and stored in AWS
#     Secrets Manager (or SSM Parameter Store, SecureString). It is never
#     written into a .tf file, a .tfvars file, or committed state in a public
#     repo. The app tier reads it at runtime via an IAM role.
#     Note: the generated password still lands in terraform.tfstate — state
#     must stay out of version control and should move to an encrypted remote
#     backend before any real apply.
#
#   Data protection
#     storage_encrypted = true, automated backups enabled, deletion
#     protection on for non-dev environments.
#
# Planned resources
#   random_password
#   aws_secretsmanager_secret / _secret_version  (or aws_ssm_parameter)
#   aws_db_subnet_group
#   aws_db_instance  (MySQL, Multi-AZ, encrypted, not publicly accessible)
