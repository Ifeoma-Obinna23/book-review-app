# =============================================================================
# Security module -- every security group in the three-tier architecture
# =============================================================================
#
# Owns all five security groups and the SG-to-SG rule chain that connects
# them. Nothing else in this project may create a security group (CLAUDE.md
# section 5); other modules consume the IDs exported from outputs.tf.
#
# The boundaries enforced here (CLAUDE.md sections 2 and 3):
#
#   internet        -> public ALB SG   : 80 and 443 only. The ONLY place an
#                                        unscoped 0.0.0.0/0 inbound rule is
#                                        permitted anywhere in this project.
#   public ALB SG   -> web tier SG     : web port (default 3000), by SG id.
#   trusted /32     -> web tier SG     : SSH 22, var.admin_cidr only.
#   web tier SG     -> internal ALB SG : HTTP (default 80), by SG id.
#   internal ALB SG -> app tier SG     : 3001 only, by SG id.
#   app tier SG     -> database SG     : 3306 only, by SG id.
#
# Every tier-to-tier hop is written with referenced_security_group_id, never
# with a CIDR. A CIDR-based tier hop would authorise anything that happens to
# hold an address in that range -- including a future workload placed in the
# same subnet -- whereas an SG reference authorises only the membership of the
# peer security group, which is exactly the tier boundary we mean.
#
# Why standalone aws_vpc_security_group_ingress_rule /
# aws_vpc_security_group_egress_rule resources rather than inline
# ingress/egress blocks:
#   1. The chain is mutually referential (public ALB egress -> web SG, web SG
#      ingress <- public ALB). Inline blocks would create a dependency cycle
#      between the aws_security_group resources; standalone rules break it.
#   2. Inline blocks are authoritative for the whole SG, so a rule added out
#      of band is silently reverted with no per-rule diff. Standalone rules
#      give one addressable resource, and one clear plan line, per rule.
#   3. The older aws_security_group_rule resource is superseded by these two
#      and is not used here.
#
# Default egress behaviour: the EC2 API attaches a permissive
# "allow all outbound" rule to every newly created security group. The
# aws_security_group resource deliberately revokes that rule at create time,
# so an SG declared here starts with NO egress and only gets what the
# aws_vpc_security_group_egress_rule resources below grant it. That is what
# makes the database SG's "no egress at all" posture real rather than
# aspirational -- see the database section.
#
# Tagging: the root provider sets default_tags for Project/Environment/
# ManagedBy. This module still stamps Project/Environment via
# local.common_tags so it remains correct under a root module without
# default_tags; identical key/value pairs do not produce a perpetual diff.
# Individual rule resources are intentionally left untagged -- their
# `description` is what surfaces in the console and in a plan diff.
# =============================================================================

locals {
  # Same idiom as the network module: an explicit override wins, otherwise
  # derive "<project>-<environment>".
  name_prefix = var.name_prefix != "" ? var.name_prefix : "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
    },
    var.tags,
  )

  # Ports that CLAUDE.md fixes and that are deliberately NOT variables.
  #
  # The public ALB listener ports are the only ports anywhere in this project
  # that are exposed to 0.0.0.0/0 ("Internet -> Public ALB: 443/80 only",
  # CLAUDE.md section 2). Making them inputs would turn the single permitted
  # unscoped ingress rule into a lever a caller could point at any port, so
  # they stay constants here. Likewise SSH is 22 by the same section.
  alb_http_port  = 80
  alb_https_port = 443
  ssh_port       = 22
}

# -----------------------------------------------------------------------------
# Default security group -- locked down
# -----------------------------------------------------------------------------
# Every VPC is created with a default security group that allows all traffic
# between its own members and all outbound traffic. Nothing in this project
# uses it, but it exists in the VPC and any resource launched without an
# explicit SG lands in it, so it is an ambient hole rather than a harmless
# leftover. Adopting it here with no ingress and no egress arguments makes
# Terraform strip every rule from it, so falling into it means having no
# connectivity at all -- failing closed.
#
# The empty body is the intended usage: `ingress` and `egress` are omitted,
# not set to empty blocks, and the provider removes the pre-existing rules.
# This resource ADOPTS the existing default SG into state; it does not create
# a new one, and removing it from configuration later leaves the SG in its
# then-current (locked down) state rather than restoring the open rules.

resource "aws_default_security_group" "default" {
  vpc_id = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-default-sg-locked-down"
  })
}

# -----------------------------------------------------------------------------
# Security groups
# -----------------------------------------------------------------------------
# name_prefix is used instead of name so that create_before_destroy can
# actually work: a security group name must be unique within the VPC, so any
# change forcing replacement would collide with the still-present old SG if the
# name were fixed. The human-readable name lives in the Name tag, matching the
# network module's convention.
#
# create_before_destroy is set on all five: a security group that is still
# referenced by an ENI, load balancer or RDS instance cannot be deleted, so the
# replacement has to exist (and take over the references) first.

resource "aws_security_group" "public_alb" {
  name_prefix = "${local.name_prefix}-public-alb-sg-"
  description = "Public ALB: accepts HTTP/HTTPS from the internet, forwards to the web tier only."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-alb-sg"
    Tier = "web"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "web_tier" {
  name_prefix = "${local.name_prefix}-web-tier-sg-"
  description = "Web tier (Next.js): reachable only from the public ALB, plus administrative SSH from a single trusted /32."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-tier-sg"
    Tier = "web"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "internal_alb" {
  name_prefix = "${local.name_prefix}-internal-alb-sg-"
  description = "Internal ALB: accepts HTTP from the web tier only, forwards to the app tier on the app port."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-internal-alb-sg"
    Tier = "app"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app_tier" {
  name_prefix = "${local.name_prefix}-app-tier-sg-"
  description = "Application tier (Node.js/Express): reachable only from the internal ALB; egress to MySQL and outbound HTTPS via NAT."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-tier-sg"
    Tier = "app"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${local.name_prefix}-db-sg-"
  description = "RDS MySQL: reachable only from the application tier on the MySQL port. No egress."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-sg"
    Tier = "db"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Hop 1 -- internet -> public ALB
# =============================================================================
# The only unscoped 0.0.0.0/0 ingress permitted in this project (CLAUDE.md
# section 3), and only on the two listener ports.
#
# IPv6 is deliberately not opened. The network module builds an IPv4-only VPC,
# so a ::/0 rule would grant reachability the rest of the design has not been
# reviewed for. Add cidr_ipv6 rules here only alongside IPv6 subnets/routing.
#
# Port 80 is kept open so the ALB can answer plain HTTP and redirect to HTTPS
# rather than time out. The redirect itself is a listener rule on the load
# balancer, not something a security group can express.

resource "aws_vpc_security_group_ingress_rule" "public_alb_http_from_internet" {
  security_group_id = aws_security_group.public_alb.id
  description       = "HTTP from the internet (redirected to HTTPS by the ALB listener)."

  ip_protocol = "tcp"
  from_port   = local.alb_http_port
  to_port     = local.alb_http_port
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "public_alb_https_from_internet" {
  security_group_id = aws_security_group.public_alb.id
  description       = "HTTPS from the internet."

  ip_protocol = "tcp"
  from_port   = local.alb_https_port
  to_port     = local.alb_https_port
  cidr_ipv4   = "0.0.0.0/0"
}

# The public ALB may talk to exactly one thing: the web tier, on the web port.
# This single egress rule also covers ALB target health checks, which by
# default use the target group's traffic port.
resource "aws_vpc_security_group_egress_rule" "public_alb_to_web_tier" {
  security_group_id = aws_security_group.public_alb.id
  description       = "Forward and health-check traffic to the web tier on the web port."

  ip_protocol                  = "tcp"
  from_port                    = var.web_port
  to_port                      = var.web_port
  referenced_security_group_id = aws_security_group.web_tier.id
}

# =============================================================================
# Hop 2 -- public ALB -> web tier (plus administrative SSH)
# =============================================================================

resource "aws_vpc_security_group_ingress_rule" "web_tier_from_public_alb" {
  security_group_id = aws_security_group.web_tier.id
  description       = "Application traffic from the public ALB only."

  ip_protocol                  = "tcp"
  from_port                    = var.web_port
  to_port                      = var.web_port
  referenced_security_group_id = aws_security_group.public_alb.id
}

# The one administrative exception in CLAUDE.md section 3. var.admin_cidr is
# validated to be a single /32 and to reject 0.0.0.0/0, so this rule cannot be
# widened by supplying a bigger prefix -- it would fail at plan time.
#
# This is the only inbound path to any compute in the project that does not
# come from a load balancer. SSM Session Manager would remove the need for it
# entirely; that is the recommended follow-up once the compute module exists,
# at which point this rule and the variable can be deleted.
resource "aws_vpc_security_group_ingress_rule" "web_tier_ssh_from_admin" {
  security_group_id = aws_security_group.web_tier.id
  description       = "Administrative SSH from the single trusted admin address."

  ip_protocol = "tcp"
  from_port   = local.ssh_port
  to_port     = local.ssh_port
  cidr_ipv4   = var.admin_cidr
}

# Web tier -> internal ALB. The web tier's only in-VPC destination.
resource "aws_vpc_security_group_egress_rule" "web_tier_to_internal_alb" {
  security_group_id = aws_security_group.web_tier.id
  description       = "Server-side API calls from the web tier to the internal ALB."

  ip_protocol                  = "tcp"
  from_port                    = var.internal_alb_port
  to_port                      = var.internal_alb_port
  referenced_security_group_id = aws_security_group.internal_alb.id
}

# Outbound internet for the web tier. Unavoidably 0.0.0.0/0 on the destination
# side: OS package mirrors, container registries and the npm registry are CDN
# hosted and have no stable address range worth pinning. This is EGRESS only --
# it grants nothing inbound, and CLAUDE.md's prohibition is on unscoped
# *inbound* rules. Scoped by port rather than by destination.
resource "aws_vpc_security_group_egress_rule" "web_tier_https_to_internet" {
  security_group_id = aws_security_group.web_tier.id
  description       = "Outbound HTTPS for OS updates, package installs and third-party APIs."

  ip_protocol = "tcp"
  from_port   = local.alb_https_port
  to_port     = local.alb_https_port
  cidr_ipv4   = "0.0.0.0/0"
}

# Plain HTTP egress exists only because several distribution package mirrors
# (and yum/apt metadata redirects) still serve over port 80. Set
# allow_plain_http_egress = false once the AMI's repositories are confirmed
# HTTPS-only; nothing in the application needs it.
resource "aws_vpc_security_group_egress_rule" "web_tier_http_to_internet" {
  count = var.allow_plain_http_egress ? 1 : 0

  security_group_id = aws_security_group.web_tier.id
  description       = "Outbound HTTP for OS package mirrors that do not serve over TLS."

  ip_protocol = "tcp"
  from_port   = local.alb_http_port
  to_port     = local.alb_http_port
  cidr_ipv4   = "0.0.0.0/0"
}

# =============================================================================
# Hop 3 -- web tier -> internal ALB -> app tier
# =============================================================================

resource "aws_vpc_security_group_ingress_rule" "internal_alb_from_web_tier" {
  security_group_id = aws_security_group.internal_alb.id
  description       = "HTTP from the web tier only."

  ip_protocol                  = "tcp"
  from_port                    = var.internal_alb_port
  to_port                      = var.internal_alb_port
  referenced_security_group_id = aws_security_group.web_tier.id
}

# The internal ALB has exactly one destination and one port. Note there is no
# rule anywhere granting the public ALB access to this SG or to the app tier:
# CLAUDE.md section 3 forbids the public ALB reaching the app tier directly.
resource "aws_vpc_security_group_egress_rule" "internal_alb_to_app_tier" {
  security_group_id = aws_security_group.internal_alb.id
  description       = "Forward and health-check traffic to the app tier on the app port."

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.app_tier.id
}

resource "aws_vpc_security_group_ingress_rule" "app_tier_from_internal_alb" {
  security_group_id = aws_security_group.app_tier.id
  description       = "Application traffic from the internal ALB only."

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.internal_alb.id
}

# =============================================================================
# Hop 4 -- app tier -> database, and app tier outbound via NAT
# =============================================================================

resource "aws_vpc_security_group_egress_rule" "app_tier_to_database" {
  security_group_id = aws_security_group.app_tier.id
  description       = "MySQL queries to the RDS instance."

  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.database.id
}

# The app tier sits in private subnets, so this egress can only leave via the
# NAT gateways -- outbound-only by construction. Needed for package installs,
# Secrets Manager / SSM API calls and any third-party HTTPS the backend makes.
resource "aws_vpc_security_group_egress_rule" "app_tier_https_to_internet" {
  security_group_id = aws_security_group.app_tier.id
  description       = "Outbound HTTPS via NAT for AWS APIs, package installs and third-party services."

  ip_protocol = "tcp"
  from_port   = local.alb_https_port
  to_port     = local.alb_https_port
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_tier_http_to_internet" {
  count = var.allow_plain_http_egress ? 1 : 0

  security_group_id = aws_security_group.app_tier.id
  description       = "Outbound HTTP via NAT for OS package mirrors that do not serve over TLS."

  ip_protocol = "tcp"
  from_port   = local.alb_http_port
  to_port     = local.alb_http_port
  cidr_ipv4   = "0.0.0.0/0"
}

# =============================================================================
# Hop 5 -- database
# =============================================================================
# One ingress rule, from the app tier security group, on the MySQL port. That
# is the entire attack surface of the data tier.

resource "aws_vpc_security_group_ingress_rule" "database_from_app_tier" {
  security_group_id = aws_security_group.database.id
  description       = "MySQL from the application tier only."

  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.app_tier.id
}

# EGRESS: deliberately none. There is no aws_vpc_security_group_egress_rule
# for this security group anywhere in the module, and that is the whole point.
#
# Why this works rather than silently leaving the AWS default in place: the
# EC2 API adds an allow-all egress rule to every new security group, but the
# aws_security_group resource revokes it during creation, so an SG with no
# egress rule resources attached ends up with genuinely zero egress. (This
# behaviour is a property of the provider's create path, not of the schema --
# confirm it in the `terraform plan`/apply output before relying on it.)
#
# Why zero egress is sufficient: security groups are stateful. Query responses
# to the app tier flow back on the established connection without needing an
# egress rule. RDS's own management traffic -- backups to S3, Multi-AZ
# replication, patching, monitoring -- runs over the AWS-managed side of the
# instance and is not governed by this customer security group.
#
# Why not "scoped egress back to the app tier": a return rule of
# 3306 -> app tier SG would be unused (statefulness already covers replies)
# and an ephemeral-port rule to the app tier SG would authorise the database
# to originate connections into the application tier, which is a reversal of
# the trust direction and a textbook exfiltration path. No egress is both
# tighter and simpler to review.
#
# If a genuine need appears later (e.g. RDS Custom, or outbound integration),
# do NOT add 0.0.0.0/0 -- add a narrowly scoped rule to a VPC endpoint's
# prefix list via prefix_list_id, and re-review.
