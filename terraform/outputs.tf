# Outputs for the dev environment root module
#
# These re-export the module outputs that a human operator or a later module
# actually needs. All list outputs are AZ-ordered: index N of every list refers
# to the same Availability Zone as index N of `availability_zones`.
#
# Nothing here is sensitive. NAT public IPs are internet-routable addresses AWS
# publishes anyway, so they are not marked sensitive -- but they are the correct
# values to hand to any third party that needs an egress allow-list.

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = module.network.vpc_cidr_block
}

output "availability_zones" {
  description = "Availability Zone names actually used, in the order subnets and route tables were created."
  value       = module.network.availability_zones
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

output "public_web_subnet_ids" {
  description = "IDs of the public web-tier subnets, AZ-ordered. Targets for the internet-facing ALB and the web-tier ASG."
  value       = module.network.public_web_subnet_ids
}

output "private_app_subnet_ids" {
  description = "IDs of the private application-tier subnets, AZ-ordered. Targets for the internal ALB and the app-tier ASG."
  value       = module.network.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "IDs of the private database-tier subnets, AZ-ordered. Feed these to the database module's aws_db_subnet_group."
  value       = module.network.private_db_subnet_ids
}

# -----------------------------------------------------------------------------
# Egress
# -----------------------------------------------------------------------------

output "nat_gateway_public_ips" {
  description = "Elastic IP addresses of the NAT gateways, AZ-ordered. These are the source addresses the private tiers present for outbound traffic. Empty list when enable_nat_gateway is false."
  value       = module.network.nat_gateway_public_ips
}

output "nat_gateway_enabled" {
  description = "Whether NAT gateways were created. When false, the private application tier has no outbound internet path."
  value       = module.network.nat_gateway_enabled
}

# -----------------------------------------------------------------------------
# Security groups
# -----------------------------------------------------------------------------
# The five security group IDs owned by the security module. Re-exported so the
# tier boundaries are inspectable from `terraform output` without digging into
# module state. A security group ID is an identifier, not a credential --
# nothing here is sensitive.

output "public_alb_security_group_id" {
  description = "ID of the public ALB security group. The only SG in this project with a 0.0.0.0/0 inbound rule, and only on 80/443."
  value       = module.security.public_alb_security_group_id
}

output "web_tier_security_group_id" {
  description = "ID of the web tier security group. Inbound from the public ALB SG on the web port, plus administrative SSH from admin_cidr."
  value       = module.security.web_tier_security_group_id
}

output "internal_alb_security_group_id" {
  description = "ID of the internal ALB security group. Inbound from the web tier SG only."
  value       = module.security.internal_alb_security_group_id
}

output "app_tier_security_group_id" {
  description = "ID of the application tier security group. Inbound from the internal ALB SG only, on port 3001."
  value       = module.security.app_tier_security_group_id
}

output "database_security_group_id" {
  description = "ID of the RDS MySQL security group. Inbound from the app tier SG only, on port 3306, with no egress."
  value       = module.security.database_security_group_id
}

# -----------------------------------------------------------------------------
# Load balancers
# -----------------------------------------------------------------------------

output "public_alb_dns_name" {
  description = "DNS name of the public ALB. The app's single internet-facing entry point; point a Route 53 alias record at this."
  value       = module.load_balancer.public_alb_dns_name
}

output "public_alb_arn" {
  description = "ARN of the public ALB."
  value       = module.load_balancer.public_alb_arn
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB. Never publicly resolvable/reachable -- this is what the web tier's server-side code calls to reach the app tier."
  value       = module.load_balancer.internal_alb_dns_name
}

output "web_target_group_arn" {
  description = "ARN of the web tier target group, attached by the web-tier ASG (compute module)."
  value       = module.load_balancer.web_target_group_arn
}

output "app_target_group_arn" {
  description = "ARN of the app tier target group (port 3001), attached by the app-tier ASG (compute module) and forwarded to only by the internal ALB."
  value       = module.load_balancer.app_target_group_arn
}
