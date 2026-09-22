# =============================================================================
# Root module -- Book Review App (dev environment)
# =============================================================================
#
# Composes the modules that exist today. Per CLAUDE.md sections 2 and 3 the
# full architecture is:
#
#   internet -> public ALB (public web subnets, 80/443)
#            -> web tier   (Next.js)
#            -> internal ALB (private app subnets)
#            -> app tier   (Node.js/Express, 3001)
#            -> RDS MySQL  (private db subnets, 3306)
#
# `network`, `security` and `load-balancer` are wired up here. The compute and
# database modules are still scaffolds and are deliberately NOT called --
# instantiating them would either fail validation or silently create nothing.
# They get added as each one is built out and reviewed.
# =============================================================================

# -----------------------------------------------------------------------------
# Network -- VPC, six subnets (web/app/db x 2 AZs), IGW, NAT, route tables
# -----------------------------------------------------------------------------

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr                 = var.vpc_cidr
  public_web_subnet_cidrs  = var.public_web_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs

  # Empty by default: the module derives AZs from aws_availability_zones for
  # whatever region the provider is pointed at, so the config stays portable.
  availability_zones = var.availability_zones

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # Internet reachability for the web tier comes from the public ALB, not from
  # instance-level public IPs. Left false.
  public_subnet_map_public_ip_on_launch = var.public_subnet_map_public_ip_on_launch

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security -- every security group in the architecture
# -----------------------------------------------------------------------------
# Owns all five security groups (public ALB, web, internal ALB, app, db) and
# the SG-to-SG rules that chain them, and locks down the VPC's default
# security group. No other module may create a security group; they consume
# the IDs this one exports.
#
# vpc_id is taken from the network module's output rather than a variable or a
# data lookup, which makes the dependency explicit and keeps the security
# groups pinned to the VPC this root config actually built.
#
# Port inputs (web_port, internal_alb_port, app_port, db_port) are left at the
# module's defaults -- 3000 / 80 / 3001 / 3306, matching CLAUDE.md section 2 --
# rather than surfaced as root variables. They belong to the architecture, not
# to the environment, and the compute and database modules will need to agree
# with them; promoting them to the root would suggest they are per-environment
# knobs. Promote them if and when a second environment genuinely differs.

module "security" {
  source = "./modules/security"

  vpc_id = module.network.vpc_id

  project_name = var.project_name
  environment  = var.environment

  # Sole administrative ingress path in the whole project. No default anywhere
  # in the chain: it must be supplied deliberately, per invocation.
  admin_cidr = var.admin_cidr

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Load balancer -- public ALB + internal ALB, their listeners and target groups
# -----------------------------------------------------------------------------
# vpc_id and every subnet ID come from the network module's outputs; both
# security group IDs come from the security module's outputs. This module
# never creates a security group of its own (CLAUDE.md section 5).
#
# web_port / internal_alb_port / app_port are left at the load-balancer
# module's defaults (3000 / 80 / 3001) rather than surfaced as root
# variables, for the same reason the security module's port inputs aren't:
# they must agree with the security module's own port defaults to keep the
# SG-to-SG rule chain, the ALB listeners and the target groups pointed at the
# same numbers. Promoting only one side to a root variable would invite drift
# between the two modules.
#
# Health check tuning and deletion protection ARE genuine per-environment
# operational knobs -- they don't need to match anything in the security
# module -- so those are surfaced as root variables below.

module "load_balancer" {
  source = "./modules/load-balancer"

  vpc_id                 = module.network.vpc_id
  public_subnet_ids      = module.network.public_web_subnet_ids
  private_app_subnet_ids = module.network.private_app_subnet_ids

  public_alb_security_group_id   = module.security.public_alb_security_group_id
  internal_alb_security_group_id = module.security.internal_alb_security_group_id

  web_health_check_healthy_threshold   = var.web_health_check_healthy_threshold
  web_health_check_unhealthy_threshold = var.web_health_check_unhealthy_threshold
  web_health_check_interval            = var.web_health_check_interval

  app_health_check_healthy_threshold   = var.app_health_check_healthy_threshold
  app_health_check_unhealthy_threshold = var.app_health_check_unhealthy_threshold
  app_health_check_interval            = var.app_health_check_interval

  enable_deletion_protection = var.enable_deletion_protection

  project_name = var.project_name
  environment  = var.environment

  tags = var.tags
}
