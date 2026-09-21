# Outputs for the load-balancer module.
#
# To be added once the load balancers exist. Expected surface:
#   public_alb_dns_name          — the app's public entry point
#   public_alb_zone_id           — for a Route 53 alias record
#   web_target_group_arn         — attached by the web tier ASG
#   internal_alb_dns_name        — what the web tier calls for API traffic
#   app_target_group_arn         — attached by the app tier ASG (port 3001)
