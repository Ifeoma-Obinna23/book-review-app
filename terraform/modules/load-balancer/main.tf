# Load balancer module — scaffold only, no resources yet.
#
# Purpose
#   Creates both load balancers that front the web and app tiers, plus their
#   listeners and target groups.
#
# Security boundaries this module must enforce (CLAUDE.md sections 2 and 3)
#
#   Public ALB
#     internal = false
#     Placed in public-web-subnet-az1 and public-web-subnet-az2 (2 AZs).
#     The only internet-facing entry point in the whole architecture.
#     Listeners: 443 (and 80, redirecting to 443). Nothing else.
#     Targets the web tier (Next.js) on its app port.
#
#   Internal ALB
#     internal = true — no public IP, no public DNS.
#     Placed in private-app-subnet-az1 and private-app-subnet-az2 (2 AZs).
#     Reachable only from the web tier security group.
#     Targets the app tier (Node.js/Express) on port 3001 ONLY.
#
#   Both load balancers must span at least 2 Availability Zones.
#   The public ALB must never target the app tier directly.
#
# Planned resources
#   aws_lb                x2 (public, internal)
#   aws_lb_target_group   x2 (web tier, app tier :3001)
#   aws_lb_listener       public 80 -> redirect 443, public 443 -> web tg,
#                         internal HTTP -> app tg
