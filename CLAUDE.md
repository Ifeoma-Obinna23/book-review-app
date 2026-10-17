# Book Review App — Terraform Capstone (Claude Code Project Context)

## 1. Project Summary
This project deploys the Book Review App (Next.js frontend, Node.js/Express backend,
MySQL database) onto **AWS** using Terraform, in a production-style three-tier
architecture. Claude Code is used as an engineering assistant throughout —
for planning, module design, code generation, documentation research, security
review, and troubleshooting. It is NOT authorized to make infrastructure-changing
decisions unilaterally. A human engineer reviews and approves every plan and apply.

Cloud platform: **AWS** (update this line if you switch to Azure)

## 2. Target Architecture

Internet
  -> Public Application Load Balancer (public subnets)
  -> Web Tier (Next.js, private-ish/public per design, autoscaling group)
  -> Internal Load Balancer (private subnets)
  -> Application Tier (Node.js/Express, private subnets, port 3001)
  -> Managed MySQL (RDS, private DB subnets, port 3306)

### Six-Subnet Design (3 tiers x 2 Availability Zones)
- `public-web-subnet-az1`, `public-web-subnet-az2`   — Public Load Balancer, NAT Gateway(s), Web Tier (Next.js) compute
- `private-app-subnet-az1`, `private-app-subnet-az2` — Internal Load Balancer, Application Tier (Node.js/Express) compute
- `private-db-subnet-az1`, `private-db-subnet-az2`   — RDS MySQL (Multi-AZ)

This gives three distinct tiers across two Availability Zones each:
- **Public Web Tier** — public subnets, reachable from the internet only via
  the public load balancer
- **Private Application Tier** — private subnets, reachable only from the
  internal load balancer
- **Private Database Tier** — private subnets, reachable only from the
  application tier's security group

### Traffic & Port Rules
- Internet -> Public ALB: 443/80 only
- Public ALB -> Web Tier: HTTP (app-defined port, e.g. 3000)
- Web Tier -> Internal ALB: HTTP
- Internal ALB -> App Tier: **3001** only
- App Tier -> MySQL (RDS): **3306** only
- The app tier reaches the internet only via NAT Gateway (outbound only); web tier instances in public subnets use the Internet Gateway through their public IPs
- The database tier has NO public IP and NO route to an Internet Gateway

## 3. Security Boundaries (non-negotiable)
- Frontend/web tier: reachable only via the public load balancer, plus the
  single administrative SSH exception below
- Backend/app tier: reachable only from the internal load balancer — never from
  the internet, and never directly from the public ALB
- Database tier: reachable only from the app tier security group, on 3306
- No security group or NSG may contain an unscoped `0.0.0.0/0` inbound rule
  except on the public ALB's listener ports
- No compute resource in the app or db tier may have a public IP
- Web tier instances run in public subnets and may hold public IPs for outbound
  access. Their security group accepts traffic only from the public ALB SG, plus
  administrative SSH (22) from a single trusted /32 supplied as a variable —
  never 0.0.0.0/0
- All resources must be spread across at least 2 Availability Zones where the
  service supports it (subnets, ALB targets, RDS Multi-AZ)

## 4. Secrets Handling
- No cloud credentials, DB passwords, SSH private keys, JWT secrets, or access
  tokens may appear in Terraform files, CLAUDE.md, commit history, or chat logs
- Database credentials are provisioned via `random_password` / AWS Secrets
  Manager (or SSM Parameter Store), never hardcoded in `.tf` files
- `terraform.tfstate` must never be committed to a public repository
- Add `*.tfstate`, `*.tfvars` (with secrets), and `.terraform/` to `.gitignore`

## 5. Terraform Requirements

### Repository Layout (as built)
```
terraform/
  main.tf         — root config; composes the modules
  variables.tf    — root input variables
  outputs.tf      — root outputs (re-exported module outputs)
  providers.tf    — terraform{} required_version/required_providers + aws provider
  modules/
    network/        VPC, 6 subnets, IGW, NAT, route tables
    security/       all security groups and the SG-to-SG rule chain
    load-balancer/  public ALB + internal ALB
    compute/        web tier and app tier compute
    database/       RDS MySQL
```

- The root config lives directly in `/terraform` — there is no
  `environments/dev` directory. A single `dev` environment is assumed; the
  environment name is carried by the `environment` variable, not by the
  directory path. If a second environment is ever added, that is the point to
  introduce `environments/` and revisit this.
- Every module must define `variables.tf`, `main.tf`, and `outputs.tf`. A
  module may add `versions.tf` for its own `required_providers` constraints
  (`network` does).
- Only the `security` module may create security groups. Every other module
  consumes the SG IDs it exports.

### Build Status
Modules are built out one at a time, each reviewed before the next starts.
Keep this list current — the root `main.tf` must only instantiate modules
that actually contain resources.

| Module | Status |
|---|---|
| `network` | **Built** — real resources, wired into root `main.tf` |
| `security` | **Built** — five SGs + SG-to-SG rule chain + default-SG lockdown, wired into root `main.tf` |
| `load-balancer` | **Built** — public ALB + internal ALB, listeners, target groups, wired into root `main.tf` |
| `database` | **Built** — RDS MySQL, wired into root `main.tf` |
| `compute` | **Built** — shared AMI/IAM in `main.tf`, web tier in `web.tf`, app tier in `app.tf`, wired into root `main.tf` |

Resolved: `compute` stayed a single module rather than splitting into
`compute-web` / `compute-app`. Both tiers share one AMI data source and one
IAM role/instance profile (`main.tf`), with tier-specific launch
template/ASG resources split into `web.tf` and `app.tf`.

- Run `terraform fmt` and `terraform validate` after every change (enforced by
  hooks — see `.claude/settings.json`)
- Use the Terraform MCP server for current provider/resource documentation —
  do not rely on possibly-outdated training knowledge for resource arguments
- Always inspect `terraform plan` output before approving an apply

## 6. Human-in-the-Loop Rules (hard requirements)
- Claude Code may propose Terraform code, run `terraform fmt`, `terraform
  validate`, and `terraform plan`
- Claude Code must NEVER run `terraform apply` or `terraform destroy`
  automatically or without explicit, per-action human confirmation
- Claude Code must never weaken a security control (open a port, widen a CIDR,
  remove an NSG/SG rule) just to make the application reachable — flag the
  issue and propose the least-privilege fix instead
- If Claude Code is uncertain about a resource argument or best practice, it
  must consult the Terraform MCP server or official docs rather than guess

## 7. Subagents
- **terraform-engineer**: architecture planning, module design, resource
  authoring, variables/outputs, refactoring, validation troubleshooting,
  provider/resource research via MCP
- **architecture-security-reviewer**: reviews (does not author) — subnet
  separation, routing, NAT design, SG/NSG rules, public IP exposure, port
  3001/3306 boundaries, load balancer placement, DB exposure, AZ coverage,
  secrets handling, module boundaries

## 8. Validation Hooks
On every Terraform file change:
`terraform fmt` -> `terraform validate` -> report result back to the user.
See `.claude/settings.json` for hook wiring. Hooks are deterministic checks
only — they do not run `plan`, `apply`, or `destroy`.