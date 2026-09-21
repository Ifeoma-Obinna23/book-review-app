# Input variables for the network module.
#
# Subnet CIDRs are expressed as *lists* (one entry per Availability Zone)
# rather than six individual scalar variables. Rationale:
#   - The module is not hard-wired to exactly two AZs. Growing to three AZs is
#     a change to three default values, not six new variables plus six new
#     resource blocks.
#   - Resources can be built with `count`/index, which keeps AZ ordering
#     consistent across subnets, NAT gateways, and route tables. Index N of
#     every list always refers to the same AZ.
#   - Outputs are naturally AZ-ordered lists, which is the shape the
#     load-balancer, compute, and database modules want.

variable "project_name" {
  description = "Project identifier used to build resource names (e.g. \"book-review-app\"). Project/Environment/ManagedBy tags come from the root provider's default_tags, so this is used for naming only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 characters of lowercase letters, digits, or hyphens, and may not start or end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod). Used for resource naming only."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "name_prefix" {
  description = "Optional explicit prefix for every resource name in this module. Leave empty (the default) to derive it as \"<project_name>-<environment>\", which is what every sibling module does."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged onto this module's common tag set. The root provider's default_tags already supply Project/Environment/ManagedBy, so this is for extra, caller-specific tags only."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Must be large enough to contain every subnet CIDR supplied below."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, for example \"10.0.0.0/16\"."
  }

  validation {
    # The can() guard keeps a malformed CIDR from blowing up expression
    # evaluation here; the validation above reports that case properly.
    condition     = !can(cidrnetmask(var.vpc_cidr)) || tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "vpc_cidr must be /24 or larger (smaller prefix length) to hold six /24 subnets."
  }
}

variable "public_web_subnet_cidrs" {
  description = "CIDR blocks for the PUBLIC web-tier subnets, one per Availability Zone, in AZ order. These host the public ALB and the NAT gateways."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_web_subnet_cidrs) >= 2
    error_message = "public_web_subnet_cidrs must contain at least 2 entries; CLAUDE.md section 3 requires every tier to span at least 2 Availability Zones."
  }

  validation {
    condition     = alltrue([for c in var.public_web_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry in public_web_subnet_cidrs must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = length(distinct(var.public_web_subnet_cidrs)) == length(var.public_web_subnet_cidrs)
    error_message = "public_web_subnet_cidrs must not contain duplicate CIDR blocks."
  }
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for the PRIVATE application-tier subnets, one per Availability Zone, in AZ order. These host the internal ALB and the Node.js/Express compute."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_app_subnet_cidrs) >= 2
    error_message = "private_app_subnet_cidrs must contain at least 2 entries; CLAUDE.md section 3 requires every tier to span at least 2 Availability Zones."
  }

  validation {
    condition     = alltrue([for c in var.private_app_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry in private_app_subnet_cidrs must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = length(distinct(var.private_app_subnet_cidrs)) == length(var.private_app_subnet_cidrs)
    error_message = "private_app_subnet_cidrs must not contain duplicate CIDR blocks."
  }
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for the PRIVATE database-tier subnets, one per Availability Zone, in AZ order. These host RDS MySQL (Multi-AZ) and have no route off the VPC."
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]

  validation {
    condition     = length(var.private_db_subnet_cidrs) >= 2
    error_message = "private_db_subnet_cidrs must contain at least 2 entries; an RDS DB subnet group requires subnets in at least 2 Availability Zones."
  }

  validation {
    condition     = alltrue([for c in var.private_db_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry in private_db_subnet_cidrs must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = length(distinct(var.private_db_subnet_cidrs)) == length(var.private_db_subnet_cidrs)
    error_message = "private_db_subnet_cidrs must not contain duplicate CIDR blocks."
  }
}

variable "availability_zones" {
  description = "Optional explicit list of Availability Zone names, in the order subnet CIDRs should be assigned. Leave empty (the default) to derive AZs from the aws_availability_zones data source for the provider's region, which keeps the module region-portable."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "availability_zones must either be empty (auto-discover) or contain at least 2 zone names."
  }

  validation {
    condition     = length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "availability_zones must not contain duplicate zone names."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways (one per AZ) to give the private application tier outbound-only internet access. Set to false to stand up the VPC without NAT while iterating -- each NAT gateway costs roughly USD 65/month plus data processing. With this false the app tier has no egress and the private app route tables carry only the local route, which fails closed rather than open."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "When true, create ONE shared NAT gateway for all Availability Zones instead of one per AZ. Only honoured when enable_nat_gateway is true. Defaults to false: a NAT gateway is a zonal resource, so a single shared NAT makes the surviving AZ's egress depend on the failed AZ. Set true only in throwaway dev environments where the ~USD 65/month per-NAT cost matters more than AZ independence."
  type        = bool
  default     = false
}

variable "public_subnet_map_public_ip_on_launch" {
  description = "Whether ENIs launched into the PUBLIC web subnets receive an auto-assigned public IPv4 address. Defaults to false: the public ALB is the only intended internet-facing entry point, and web-tier instances should receive public IPs (if ever needed) via an explicit launch template network_interface setting rather than implicitly by subnet. There is deliberately no equivalent variable for the app or db subnets -- CLAUDE.md section 3 forbids public IPs there, so it is hardcoded false and cannot be overridden through this module's interface."
  type        = bool
  default     = false
}
