# Outputs for the security module.
#
# Only the five security group IDs are exported. Consumers reference these so
# that every cross-tier rule stays SG-to-SG rather than CIDR-based, and so
# that no other module is ever tempted to create a security group of its own
# (CLAUDE.md section 5).
#
# ARNs are not exported: nothing in the architecture needs them, and an unused
# output is one more thing to keep correct. Nothing here is sensitive -- a
# security group ID is an identifier, not a credential.
#
# The locked-down default security group is deliberately NOT exported. It
# exists only to be emptied; exporting its ID would invite something to attach
# to it.

output "public_alb_security_group_id" {
  description = "ID of the public ALB security group. Attach to the internet-facing ALB in the public web subnets. Accepts 80/443 from the internet."
  value       = aws_security_group.public_alb.id
}

output "web_tier_security_group_id" {
  description = "ID of the web tier (Next.js) security group. Attach to the web-tier launch template / ASG. Accepts the web port from the public ALB SG and SSH from the administrative /32 only."
  value       = aws_security_group.web_tier.id
}

output "internal_alb_security_group_id" {
  description = "ID of the internal ALB security group. Attach to the internal ALB in the private app subnets. Accepts HTTP from the web tier SG only."
  value       = aws_security_group.internal_alb.id
}

output "app_tier_security_group_id" {
  description = "ID of the application tier (Node.js/Express) security group. Attach to the app-tier launch template / ASG. Accepts the app port from the internal ALB SG only."
  value       = aws_security_group.app_tier.id
}

output "database_security_group_id" {
  description = "ID of the RDS MySQL security group. Attach to the DB instance. Accepts the MySQL port from the app tier SG only, and has no egress."
  value       = aws_security_group.database.id
}
