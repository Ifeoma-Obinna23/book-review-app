# Inputs for the security module.
#
# Ports are variables so no rule in main.tf carries a magic number, but two
# groups of ports are NOT inputs and live as locals in main.tf instead:
#   - the public ALB listener ports (80/443), because they are the only ports
#     exposed to 0.0.0.0/0 and must not be caller-controlled
#   - SSH (22)
# Both are fixed by CLAUDE.md section 2.

variable "vpc_id" {
  description = "ID of the VPC the security groups are created in. Also identifies the default security group that this module locks down."
  type        = string
}

variable "project_name" {
  description = "Project identifier used for resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)."
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

# -----------------------------------------------------------------------------
# Administrative access
# -----------------------------------------------------------------------------

variable "admin_cidr" {
  description = "Single trusted IPv4 address, in /32 CIDR form, permitted to reach the web tier on SSH (22). This is the only inbound path to any compute in the project that does not originate from a load balancer, so it is deliberately a host address rather than a range. CLAUDE.md section 3 forbids 0.0.0.0/0 here. No default: an administrative ingress rule should never be created by accident."
  type        = string

  validation {
    # Three independent checks, in the order a wrong value usually fails:
    #   1. it parses as an IPv4 CIDR at all (cidrnetmask errors otherwise, so
    #      it is wrapped in can())
    #   2. it is a single host, /32 -- this is what stops a range being slipped
    #      in, and it implicitly rejects 0.0.0.0/0 as well
    #   3. 0.0.0.0/0 is rejected by name anyway, so the error message can say
    #      so explicitly rather than making the reader infer it from the /32
    #      rule
    condition = (
      can(cidrnetmask(var.admin_cidr)) &&
      endswith(var.admin_cidr, "/32") &&
      var.admin_cidr != "0.0.0.0/0"
    )
    error_message = "admin_cidr must be a single valid IPv4 host address in CIDR form with a /32 suffix, for example \"203.0.113.10/32\". Ranges and 0.0.0.0/0 are rejected: CLAUDE.md section 3 allows administrative SSH only from one trusted address. Widen this only by changing the architecture decision, not the variable."
  }
}

# -----------------------------------------------------------------------------
# Application ports
# -----------------------------------------------------------------------------

variable "web_port" {
  description = "TCP port the Next.js web tier listens on. The public ALB is the only source allowed to reach it."
  type        = number
  default     = 3000

  validation {
    condition     = var.web_port > 0 && var.web_port <= 65535
    error_message = "web_port must be a valid TCP port between 1 and 65535."
  }
}

variable "internal_alb_port" {
  description = "TCP listener port on the internal ALB. Plain HTTP inside the VPC per CLAUDE.md section 2 (\"Web Tier -> Internal ALB: HTTP\"); the web tier is the only source allowed to reach it."
  type        = number
  default     = 80

  validation {
    condition     = var.internal_alb_port > 0 && var.internal_alb_port <= 65535
    error_message = "internal_alb_port must be a valid TCP port between 1 and 65535."
  }
}

variable "app_port" {
  description = "TCP port the Node.js/Express application tier listens on. ARCHITECTURAL CONSTANT: CLAUDE.md section 2 fixes this at 3001 (\"Internal ALB -> App Tier: 3001 only\"). It is a variable so the rules in main.tf are not littered with literals, not because it is free to change -- changing it departs from the documented architecture and must be reflected in CLAUDE.md and in the compute module's listener."
  type        = number
  default     = 3001

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "app_port must be a valid TCP port between 1 and 65535."
  }
}

variable "db_port" {
  description = "TCP port the RDS MySQL instance listens on. ARCHITECTURAL CONSTANT: CLAUDE.md section 2 fixes this at 3306 (\"App Tier -> MySQL (RDS): 3306 only\"). Variable-ised for readability only -- changing it departs from the documented architecture and must be kept in sync with the database module's port."
  type        = number
  default     = 3306

  validation {
    condition     = var.db_port > 0 && var.db_port <= 65535
    error_message = "db_port must be a valid TCP port between 1 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Outbound internet posture
# -----------------------------------------------------------------------------

variable "allow_plain_http_egress" {
  description = "Whether the web and app tiers may make outbound connections on port 80 in addition to 443. Defaults to true because several OS package mirrors and yum/apt metadata redirects still serve over plain HTTP; nothing in the application itself needs it. Set false for the tighter posture once the chosen AMI's repositories are confirmed HTTPS-only. This affects EGRESS only and opens no inbound path. Neither the database tier nor any load balancer SG is affected."
  type        = bool
  default     = true
}
