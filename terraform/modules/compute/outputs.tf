# Outputs for the compute module.
#
# Nothing sensitive is exported. No secrets, no user-data content (which
# contains only placeholder credential values, never real ones -- see
# templates/app_user_data.sh.tpl).

output "web_autoscaling_group_name" {
  description = "Name of the web-tier Auto Scaling Group."
  value       = aws_autoscaling_group.web.name
}

output "app_autoscaling_group_name" {
  description = "Name of the app-tier Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "instance_role_arn" {
  description = "ARN of the IAM role shared by the web-tier and app-tier instance profiles. Consumed by anything that needs to grant this role additional access later (e.g. the database module scoping a Secrets Manager resource policy)."
  value       = aws_iam_role.instance.arn
}
