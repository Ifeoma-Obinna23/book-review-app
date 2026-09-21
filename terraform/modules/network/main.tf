# =============================================================================
# Network module -- Book Review App three-tier VPC
# =============================================================================
#
# Builds the VPC, six subnets (web/app/db x 2 AZs), one internet gateway, one
# NAT gateway per AZ, and the route tables that enforce the tier boundaries
# described in CLAUDE.md sections 2 and 3.
#
# This module deliberately creates NO security groups. The `security` module
# owns those; this module only exposes the ids and CIDRs that module needs.
#
# Tagging: the root provider also sets default_tags for Project / Environment /
# ManagedBy. This module nonetheless stamps Project/Environment itself via
# local.common_tags so it stays correct if it is ever consumed by a root module
# whose provider has no default_tags. Identical key/value pairs between
# default_tags and resource tags do not produce a perpetual diff.
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # An explicit override wins; otherwise derive the prefix from project and
  # environment, which is what every sibling module does.
  name_prefix = var.name_prefix != "" ? var.name_prefix : "${var.project_name}-${var.environment}"

  # Tags applied to every resource in this module, before the per-resource
  # Name/Tier tags are merged on top. var.tags is merged last so a caller can
  # add (but not silently break) tagging.
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
    },
    var.tags,
  )

  # One AZ per entry in the public subnet CIDR list. An explicit
  # var.availability_zones wins; otherwise take the first N available zones in
  # the provider's region so the module is not pinned to region-specific
  # strings like "us-east-1a".
  # min() keeps slice() from erroring outright in a region with fewer AZs than
  # requested; the aws_vpc precondition below then reports the real problem
  # with an actionable message instead of a raw index-out-of-range error.
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    data.aws_availability_zones.available.names,
    0,
    min(length(data.aws_availability_zones.available.names), length(var.public_web_subnet_cidrs)),
  )

  # Deliberately min() rather than length(local.availability_zones): count must
  # never exceed the CIDR lists, or a mismatch surfaces as an opaque
  # "index out of range" on a subnet's cidr_block instead of the actionable
  # precondition message on aws_vpc below.
  az_count = min(length(local.availability_zones), length(var.public_web_subnet_cidrs))

  # One NAT gateway per AZ by default (see routing notes below); one shared NAT
  # when single_nat_gateway is set for dev cost savings; none when NAT is off.
  nat_gateway_count = (
    var.enable_nat_gateway
    ? (var.single_nat_gateway ? 1 : local.az_count)
    : 0
  )
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
# DNS support + DNS hostnames are both required: RDS hands out a DNS endpoint
# and private hosted-zone / VPC-endpoint name resolution depends on them.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = {
    Name = "${local.name_prefix}-vpc"
  }

  # Cross-variable invariants. Kept as preconditions rather than variable
  # `validation` blocks so the module still works on Terraform 1.5.x, which
  # cannot reference other variables from inside a validation block.
  lifecycle {
    precondition {
      condition = (
        length(var.public_web_subnet_cidrs) == length(var.private_app_subnet_cidrs) &&
        length(var.public_web_subnet_cidrs) == length(var.private_db_subnet_cidrs)
      )
      error_message = "public_web_subnet_cidrs, private_app_subnet_cidrs and private_db_subnet_cidrs must all be the same length -- one CIDR per Availability Zone, in AZ order."
    }

    precondition {
      condition     = local.az_count == length(var.public_web_subnet_cidrs)
      error_message = "Not enough Availability Zones. The region reported ${length(data.aws_availability_zones.available.names)} available zone(s) but ${length(var.public_web_subnet_cidrs)} subnet CIDR(s) per tier were supplied. Choose a region with more AZs, set var.availability_zones explicitly, or shorten the subnet CIDR lists."
    }
  }
}

# -----------------------------------------------------------------------------
# Internet gateway
# -----------------------------------------------------------------------------
# The single ingress/egress point to the internet. Only the public route table
# ever references it -- the app and db route tables must never carry a route
# to this gateway (CLAUDE.md section 2, "Traffic & Port Rules").

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# -----------------------------------------------------------------------------
# Subnets -- public web tier
# -----------------------------------------------------------------------------
# Hosts the internet-facing ALB, the NAT gateways, and the Next.js web tier.
#
# map_public_ip_on_launch defaults to FALSE. Internet reachability for the web
# tier is provided by the public ALB, not by instance-level public IPs, and
# outbound access is via NAT. If the web tier ever genuinely needs a public IP,
# assign it explicitly in the ASG launch template rather than making every ENI
# in the subnet public by default.

resource "aws_subnet" "public_web" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_web_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = var.public_subnet_map_public_ip_on_launch

  tags = {
    Name = "${local.name_prefix}-public-web-subnet-az${count.index + 1}"
    Tier = "web"
  }
}

# -----------------------------------------------------------------------------
# Subnets -- private application tier
# -----------------------------------------------------------------------------
# Hosts the internal ALB and the Node.js/Express compute (port 3001).
# map_public_ip_on_launch is hardcoded false and intentionally NOT variable:
# CLAUDE.md section 3 forbids public IPs on app-tier compute.

resource "aws_subnet" "private_app" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_app_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-app-subnet-az${count.index + 1}"
    Tier = "app"
  }
}

# -----------------------------------------------------------------------------
# Subnets -- private database tier
# -----------------------------------------------------------------------------
# Hosts RDS MySQL (Multi-AZ). No public IPs, and -- see the route table section
# -- no default route of any kind.

resource "aws_subnet" "private_db" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_db_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-db-subnet-az${count.index + 1}"
    Tier = "db"
  }
}

# -----------------------------------------------------------------------------
# NAT gateways -- one per Availability Zone
# -----------------------------------------------------------------------------
# A NAT gateway is a zonal resource. A single shared NAT would mean that losing
# its AZ also kills outbound connectivity for the app tier in the surviving AZ,
# which defeats the point of a multi-AZ deployment. One NAT per AZ keeps each
# AZ's egress path entirely inside that AZ (and avoids cross-AZ data charges).
#
# Cost note: each NAT gateway is roughly USD 65/month plus per-GB processing,
# so this design costs about 2x a single-NAT design. Set enable_nat_gateway to
# false to skip them entirely while iterating.
#
# `domain = "vpc"` is the current argument; the older boolean `vpc = true` is
# deprecated in AWS provider v5.x.

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-az${count.index + 1}"
  }

  # An EIP intended for a NAT gateway should not be allocated before the VPC
  # has an internet gateway attached.
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].allocation_id
  subnet_id     = aws_subnet.public_web[count.index].id

  # "public" is the default, but stating it makes the intent unambiguous next
  # to a "private" connectivity_type NAT, which has no internet path at all.
  connectivity_type = "public"

  tags = {
    Name = "${local.name_prefix}-nat-az${count.index + 1}"
    Tier = "web"
  }

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Route table -- public web tier (ONE, shared by both AZs)
# -----------------------------------------------------------------------------
# The only next hop here is the internet gateway, which is a regional, highly
# available VPC-attached resource with no AZ affinity. Splitting this per AZ
# would produce two byte-identical route tables, so a single shared table is
# used. (Contrast with the app tier below, where the next hop IS zonal.)

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-public-web-rt"
    Tier = "web"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_web" {
  count = local.az_count

  subnet_id      = aws_subnet.public_web[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Route tables -- private application tier (ONE PER AZ)
# -----------------------------------------------------------------------------
# Each AZ's table sends 0.0.0.0/0 to the NAT gateway living in that same AZ.
# This is the reason the NAT gateways are not collapsed into one: if AZ1 fails,
# AZ2's app subnet still egresses through AZ2's NAT, and no traffic ever has to
# cross an AZ boundary in the healthy case.
#
# These tables carry NO inbound path from the internet. NAT is outbound-only by
# construction, so the app tier remains unreachable from the internet.

resource "aws_route_table" "private_app" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-app-rt-az${count.index + 1}"
    Tier = "app"
  }
}

# Created only when NAT is enabled. When it is not, the app route tables hold
# just the implicit local route: no egress, which fails closed.
resource "aws_route" "private_app_nat" {
  count = local.nat_gateway_count

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "private_app" {
  count = local.az_count

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# -----------------------------------------------------------------------------
# Route table -- private database tier (ONE, shared, INTENTIONALLY EMPTY)
# -----------------------------------------------------------------------------
# This table is created with no aws_route resources at all. The only routing it
# provides is the implicit VPC-local route, so the db subnets can talk to the
# app tier and nothing else: no internet gateway, no NAT gateway, no egress.
# That is CLAUDE.md section 2 ("The database tier has NO public IP and NO route
# to an Internet Gateway") expressed as code rather than left to chance.
#
# Why a dedicated table instead of leaving the db subnets on the VPC main route
# table: the main route table is a mutable default that anything else in the
# account or a later `aws_main_route_table_association` could add a route to,
# and its contents are invisible in this repo. An explicit empty table makes the
# "no egress" property reviewable, diffable, and hard to break by accident.
#
# Why ONE shared table rather than one per AZ: unlike the app tier, there is no
# zonal next hop to differentiate -- the correct contents are "nothing" in every
# AZ. Two empty tables would be identical, add no failure-domain isolation, and
# give a future editor two places to make a mistake instead of one.
#
# If outbound access is ever genuinely needed here, do NOT add a NAT route.
# Add a targeted VPC endpoint instead (see the module README notes / report).

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-db-rt"
    Tier = "db"
  }
}

resource "aws_route_table_association" "private_db" {
  count = local.az_count

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}
