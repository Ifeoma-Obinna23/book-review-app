# Outputs for the load-balancer module.
#
# Nothing here is sensitive: DNS names and ARNs are identifiers, not
# credentials.

output "public_alb_dns_name" {
  description = "DNS name of the public ALB. The app's single internet-facing entry point; point a Route 53 alias record at this."
  value       = aws_lb.public.dns_name
}

output "public_alb_arn" {
  description = "ARN of the public ALB."
  value       = aws_lb.public.arn
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB. Never publicly resolvable/reachable -- this is what the web tier's server-side code calls to reach the app tier. Not a secret, but has no meaning outside the VPC."
  value       = aws_lb.internal.dns_name
}

output "web_target_group_arn" {
  description = "ARN of the web tier target group, attached by the web-tier ASG (compute module)."
  value       = aws_lb_target_group.web.arn
}

output "app_target_group_arn" {
  description = "ARN of the app tier target group (port 3001), attached by the app-tier ASG (compute module) and forwarded to only by the internal ALB."
  value       = aws_lb_target_group.app.arn
}
