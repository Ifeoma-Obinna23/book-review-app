# Load balancer module.
#
# Creates the public ALB (internet-facing) and the internal ALB (private),
# plus their listeners and target groups, per CLAUDE.md sections 2 and 3.
#
# Resource argument names below (aws_lb, aws_lb_target_group, aws_lb_listener,
# aws_lb_listener_rule) were confirmed against the installed hashicorp/aws
# ~> 5.0 provider via `terraform providers schema -json` in this session,
# because the Terraform MCP server was unavailable. Nothing here relies on
# unverified training-knowledge guesses about the schema.
#
# -----------------------------------------------------------------------------
# IMPORTANT DEVIATION FROM THE ORIGINAL SPEC -- flagged, not silently applied
# -----------------------------------------------------------------------------
# The module spec called for a second listener rule on the PUBLIC ALB, path
# pattern "/api/*", forwarding directly to an app-tier target group. That is
# NOT implemented here. Doing so would register app-tier EC2 instances as
# targets reachable directly from the internet-facing load balancer, which
# violates CLAUDE.md section 3 in two independent ways:
#   - "Backend/app tier: reachable only from the internal load balancer --
#     never from the internet, and never directly from the public ALB."
#   - The app tier security group (module.security) only allows the app port
#     from the INTERNAL ALB's security group. A public-ALB-to-app-tier target
#     group would be blocked at the network layer anyway (silent 502s), but
#     the Terraform-level design intent would still be wrong on paper, and a
#     future change to the app tier SG "to make it work" would be exactly the
#     kind of security-control weakening CLAUDE.md section 6 forbids.
#
# Safe equivalent implemented instead: the public ALB has a single listener
# whose default action forwards ALL paths -- including /api/* -- to the web
# target group. The web tier (Next.js) is the only thing the internet ever
# reaches; it is responsible for proxying /api/* requests server-side (e.g.
# via a Next.js rewrite/API route) to the INTERNAL ALB's private DNS name,
# which then reaches the app tier on port 3001. This preserves the exact
# hop-by-hop path in CLAUDE.md section 2: internet -> public ALB -> web tier
# -> internal ALB -> app tier -> RDS. The internal ALB stays fully private;
# the public ALB never gains a route to app-tier targets.

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Public ALB -- the single internet-facing entry point in the architecture
# -----------------------------------------------------------------------------

resource "aws_lb" "public" {
  name               = "${local.name_prefix}-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.public_alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  # access_logs intentionally omitted: left disabled for now, per module spec.

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-alb"
    Tier = "public-web"
  })
}

# Web target group -- the public ALB's only forwarding target.
resource "aws_lb_target_group" "web" {
  name        = "${local.name_prefix}-web-tg"
  port        = var.web_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = var.web_health_check_healthy_threshold
    unhealthy_threshold = var.web_health_check_unhealthy_threshold
    interval            = var.web_health_check_interval
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-web-tg"
    Tier = "public-web"
  })
}

# Public ALB listener, port 80.
#
# WHY a single default action and no path-based rule to the app tier:
# the public ALB is the only internet-facing entry point per CLAUDE.md's
# security boundaries. Every request -- browser page loads AND /api/* calls
# -- lands on the web tier. Path-based routing that would let /api/* reach
# the app tier happens one hop later, inside the web tier's own server-side
# code, which calls the INTERNAL ALB (never publicly reachable) to reach the
# app tier. That keeps the internal ALB fully private while still letting the
# browser's /api/* calls ultimately reach the app tier -- just not by having
# the public ALB target app-tier instances itself. See the module-level
# comment above for the full rationale and the CLAUDE.md sections it protects.
resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-http-listener"
  })
}

# -----------------------------------------------------------------------------
# Internal ALB -- private, reachable only from the web tier security group
# -----------------------------------------------------------------------------

resource "aws_lb" "internal" {
  name               = "${local.name_prefix}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.internal_alb_security_group_id]
  subnets            = var.private_app_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  # access_logs intentionally omitted: left disabled for now, per module spec.

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-internal-alb"
    Tier = "private-app"
  })
}

# App target group -- port 3001 only, per CLAUDE.md section 2.
resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = var.app_health_check_healthy_threshold
    unhealthy_threshold = var.app_health_check_unhealthy_threshold
    interval            = var.app_health_check_interval
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-app-tg"
    Tier = "private-app"
  })
}

# Internal ALB listener -- the only path into the app tier.
resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = var.internal_alb_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-internal-http-listener"
  })
}
