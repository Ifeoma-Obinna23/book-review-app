# Input variables for the dev environment root module
#
# Deep validation (CIDR well-formedness, minimum AZ count, no duplicates) lives
# in the modules that consume these values, so it is not duplicated here. These
# declarations exist to give the root config a single, documented surface and
# to supply defaults that let `terraform plan` run with no .tfvars file.

variable "aws_region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier used for resource naming and default tags."
  type        = string
  default     = "book-review-app"
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags merged onto every resource. Project/Environment/ManagedBy already come from the provider's default_tags, so this is for extra, caller-specific tags only."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Administrative access
# -----------------------------------------------------------------------------
# The one variable in this file with NO default. Every other value here is
# defaulted so `terraform plan` runs without a .tfvars file; this one is not,
# because it opens an inbound path and must be a conscious, per-operator
# choice rather than something inherited from a checked-in default. Supply it
# on the command line:
#
#   terraform plan -var="admin_cidr=203.0.113.10/32"
#
# Do not commit it to a .tfvars file in this repository -- it is not a secret,
# but a checked-in home/office address is both an information disclosure and a
# stale allow-list waiting to happen.

variable "admin_cidr" {
  description = "Single trusted IPv4 address, in /32 CIDR form, allowed to SSH (port 22) to the web tier. This is the only administrative inbound path in the architecture. CLAUDE.md section 3 requires a single trusted /32 and explicitly forbids 0.0.0.0/0 here; the security module enforces both with a variable validation block, so the check is not duplicated at the root."
  type        = string
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
# Subnet CIDRs are lists with one entry per Availability Zone, in AZ order.
# Index N of every list refers to the same AZ. The /16 is carved up as:
#   10.0.1.x  / 10.0.2.x   public web tier
#   10.0.11.x / 10.0.12.x  private app tier
#   10.0.21.x / 10.0.22.x  private db tier
# The gaps between blocks leave room to add a third AZ without renumbering.

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Must be large enough to contain every subnet CIDR below."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_web_subnet_cidrs" {
  description = "CIDR blocks for the PUBLIC web-tier subnets, one per Availability Zone, in AZ order. These host the public ALB and the NAT gateways."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for the PRIVATE application-tier subnets, one per Availability Zone, in AZ order. These host the internal ALB and the Node.js/Express compute."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for the PRIVATE database-tier subnets, one per Availability Zone, in AZ order. These host RDS MySQL (Multi-AZ) and have no route off the VPC."
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "availability_zones" {
  description = "Optional explicit list of Availability Zone names, in the order subnet CIDRs should be assigned. Leave empty (the default) to auto-discover AZs for the provider's region, which keeps this config region-portable."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways to give the private application tier outbound-only internet access. Set false to stand up the VPC without NAT while iterating -- each NAT gateway costs roughly USD 65/month plus data processing. With this false the app tier simply has no egress; it fails closed, not open."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "When true, create ONE shared NAT gateway for all AZs instead of one per AZ. Only honoured when enable_nat_gateway is true. Defaults to false: a NAT gateway is zonal, so sharing one makes the surviving AZ's egress depend on the failed AZ."
  type        = bool
  default     = false
}

variable "public_subnet_map_public_ip_on_launch" {
  description = "Whether ENIs launched into the PUBLIC web subnets get an auto-assigned public IPv4 address. Defaults to false: the public ALB is the only intended internet-facing entry point. There is deliberately no equivalent for the app or db subnets -- CLAUDE.md section 3 forbids public IPs there, so the network module hardcodes it false for those tiers."
  type        = bool
  default     = false
}
