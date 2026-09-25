# Input variables for the compute module.
#
# This module owns the web-tier and app-tier launch templates and Auto
# Scaling Groups, plus the single IAM role/instance profile shared by both
# tiers. It creates NO security groups (CLAUDE.md section 5) and NO SSH key
# pairs -- administrative access is via SSM Session Manager only, and the one
# permitted SSH exception (admin_cidr, port 22 from a single /32) is already
# enforced by the security module's web-tier security group.

# -----------------------------------------------------------------------------
# Naming / tagging
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project identifier used for resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)."
  type        = string
}

variable "tags" {
  description = "Additional tags merged onto every resource this module creates."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Networking -- IDs come from the network module's outputs
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the VPC. Required by the aws_ami data source's implicit region scoping and for clarity of intent; not directly referenced by every resource."
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the public web-tier subnets, AZ-ordered (module.network.public_web_subnet_ids). The web-tier ASG's vpc_zone_identifier."
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "IDs of the private application-tier subnets, AZ-ordered (module.network.private_app_subnet_ids). The app-tier ASG's vpc_zone_identifier."
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Security groups -- IDs come from the security module's outputs
# -----------------------------------------------------------------------------
# This module consumes SG IDs only. It must never create a security group
# (CLAUDE.md section 5, enforced by convention/review, not by Terraform).

variable "web_security_group_id" {
  description = "ID of the web-tier security group (module.security.web_tier_security_group_id). Accepts the web port from the public ALB SG and SSH from the admin /32 only."
  type        = string
}

variable "app_security_group_id" {
  description = "ID of the app-tier security group (module.security.app_tier_security_group_id). Accepts the app port from the internal ALB SG only."
  type        = string
}

# -----------------------------------------------------------------------------
# Load balancer wiring -- ARNs/DNS come from the load-balancer module's outputs
# -----------------------------------------------------------------------------

variable "web_target_group_arn" {
  description = "ARN of the web-tier target group (module.load_balancer.web_target_group_arn). Attached to the web-tier ASG."
  type        = string
}

variable "app_target_group_arn" {
  description = "ARN of the app-tier target group (module.load_balancer.app_target_group_arn). Attached to the app-tier ASG."
  type        = string
}

variable "internal_alb_dns_name" {
  description = "DNS name of the internal ALB (module.load_balancer.internal_alb_dns_name). Baked into the web tier's next.config.js so server-side API calls proxy to the app tier through the internal ALB rather than reaching it directly."
  type        = string
}

variable "internal_alb_port" {
  description = "Port the internal ALB listens on for app-tier traffic. Must match the load-balancer module's internal listener port (defaults to 80 there, per CLAUDE.md section 2 -- 'Web Tier -> Internal ALB: HTTP')."
  type        = number
  default     = 80
}

# -----------------------------------------------------------------------------
# Instance sizing
# -----------------------------------------------------------------------------

variable "web_instance_type" {
  description = "EC2 instance type for the web-tier (Next.js) launch template."
  type        = string
  default     = "t3.small"
}

variable "app_instance_type" {
  description = "EC2 instance type for the app-tier (Node.js/Express) launch template."
  type        = string
  default     = "t3.micro"
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

variable "secrets_manager_arn_pattern" {
  description = "ARN pattern (may include wildcards) for the AWS Secrets Manager secret(s) the shared web/app IAM role is allowed to read via secretsmanager:GetSecretValue. Scopes the inline policy so the role cannot read arbitrary secrets in the account. Intended for future use provisioning DB credentials once the database module exists; nothing in this module currently reads the secret."
  type        = string
  default     = "arn:aws:secretsmanager:*:*:secret:book-review-app-dev-*"
}

variable "db_secret_name" {
  description = "Name (or ARN) of the AWS Secrets Manager secret holding the app tier's DB credentials and JWT secret as JSON keys DB_HOST, DB_NAME, DB_USER, DB_PASS, JWT_SECRET. This secret does NOT exist yet -- the database module is still a scaffold (CLAUDE.md Build Status table) -- so the app-tier boot script's fetch will fail today. That failure is handled gracefully: the script falls back to REPLACE_ME_* placeholders per field rather than aborting boot, preserving the app's 'come up even if a dependency is missing' property."
  type        = string
  default     = "book-review-app-dev-db-credentials"
}

variable "app_allowed_origins" {
  description = "Comma-separated CORS-allowed origin(s) for the app tier, written verbatim into ALLOWED_ORIGINS in the app tier's .env. Not a secret. Should be set to the web tier's public-facing origin (e.g. the public ALB's DNS name, with scheme, such as https://book-review-app-dev-public-alb-123456.us-east-1.elb.amazonaws.com)."
  type        = string
}

variable "aws_region" {
  description = "AWS region passed into the app-tier boot script so the AWS CLI's secretsmanager get-secret-value call doesn't need to derive the region from IMDS at runtime. Wired from the root module's var.aws_region."
  type        = string
}

# -----------------------------------------------------------------------------
# Application source
# -----------------------------------------------------------------------------

variable "app_repo_url" {
  description = "Git URL of the Book Review App monorepo, cloned by both tiers' user data."
  type        = string
  default     = "https://github.com/Ifeoma-Obinna23/book-review-app.git"
}
