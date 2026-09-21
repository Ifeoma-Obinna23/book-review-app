# Inputs for the load-balancer module.
# Kept minimal on purpose — ports, health checks and the ACM certificate ARN
# get added when the listeners are actually written.

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

variable "public_alb_security_group_id" {
  description = "Security group ID for the internet-facing ALB, from the security module."
  type        = string
}

variable "internal_alb_security_group_id" {
  description = "Security group ID for the internal ALB, from the security module."
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
