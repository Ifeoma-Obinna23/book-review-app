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
# Only `network` and `security` are wired up here. The load-balancer, compute
# and database modules are still scaffolds and are deliberately NOT called --
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
