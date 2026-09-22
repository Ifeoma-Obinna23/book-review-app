# Inputs for the load-balancer module.

# -----------------------------------------------------------------------------
# Network wiring -- sourced from module.network in the root config
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the VPC the load balancers and target groups live in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public web subnet IDs (one per AZ) for the internet-facing ALB."
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs (one per AZ) for the internal ALB."
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Security group wiring -- sourced from module.security in the root config
# -----------------------------------------------------------------------------
# This module never creates a security group of its own (CLAUDE.md section 5:
# only the security module may create security groups).

variable "public_alb_security_group_id" {
  description = "Security group ID for the internet-facing ALB, from the security module."
  type        = string
}

variable "internal_alb_security_group_id" {
  description = "Security group ID for the internal ALB, from the security module."
  type        = string
}

# -----------------------------------------------------------------------------
# Ports
# -----------------------------------------------------------------------------
# These defaults intentionally mirror the security module's port defaults
# (web_port 3000, internal_alb_port 80, app_port 3001) so the SG-to-SG rule
# chain and the ALB listeners/target groups agree on the same numbers without
# a second source of truth. They are not surfaced as root variables for the
# same reason the security module's port inputs aren't: they describe the
# architecture, not the environment. See the root main.tf note on the
# security module invocation.

variable "web_port" {
  description = "Port the web tier (Next.js) listens on. The public ALB's web target group forwards here."
  type        = number
  default     = 3000
}

variable "internal_alb_port" {
  description = "Port the internal ALB listens on for HTTP traffic from the web tier."
  type        = number
  default     = 80
}

variable "app_port" {
  description = "Port the app tier (Node.js/Express) listens on. Must match the security module's app_port so the app tier SG's allowed port and the target group's port agree. CLAUDE.md section 2 pins this to 3001."
  type        = number
  default     = 3001
}

# -----------------------------------------------------------------------------
# Health checks
# -----------------------------------------------------------------------------
# Separate threshold/interval knobs per tier so the web and app target groups
# can be tuned independently. Health check *paths* are not variables: the web
# tier's "/" and the app tier's "/" (its health route) are fixed by CLAUDE.md's
# description of each tier and by requirements 3 and 6 of this module's spec.

variable "web_health_check_healthy_threshold" {
  description = "Consecutive successful health checks before an unhealthy web-tier target is marked healthy."
  type        = number
  default     = 3
}

variable "web_health_check_unhealthy_threshold" {
  description = "Consecutive failed health checks before a healthy web-tier target is marked unhealthy."
  type        = number
  default     = 3
}

variable "web_health_check_interval" {
  description = "Seconds between health checks against the web target group."
  type        = number
  default     = 30
}

variable "app_health_check_healthy_threshold" {
  description = "Consecutive successful health checks before an unhealthy app-tier target is marked healthy."
  type        = number
  default     = 3
}

variable "app_health_check_unhealthy_threshold" {
  description = "Consecutive failed health checks before a healthy app-tier target is marked unhealthy."
  type        = number
  default     = 3
}

variable "app_health_check_interval" {
  description = "Seconds between health checks against the app target group."
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Load balancer behavior
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = "Whether deletion protection is enabled on both the public and internal ALBs. Defaults to false so the ALBs can be torn down freely while iterating; flip to true once this environment is no longer disposable. Access logs are deliberately left disabled for both ALBs (no aws_s3_bucket / access_logs block is created by this module yet)."
  type        = bool
  default     = false
}

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
  description = "Additional tags merged onto every resource in this module."
  type        = map(string)
  default     = {}
}
