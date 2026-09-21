# Exports the network module's VPC identifiers, per-tier subnet IDs and CIDRs, gateway IDs, and route table IDs.
#
# All list outputs are AZ-ordered: index N of every list refers to the same
# Availability Zone as index N of `availability_zones`. Consumers can therefore
# zip these lists together safely.
#
# Nothing here is sensitive. NAT public IPs are internet-routable addresses that
# AWS publishes anyway, so they are not marked sensitive, but note they are the
# correct values to hand to any third party that needs an egress allow-list.

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC. Required by the security, load-balancer, compute and database modules."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC. Useful for coarse intra-VPC rules, but prefer the per-tier subnet CIDR outputs (or better, security-group references) when scoping security group rules."
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC, for IAM policy conditions and VPC endpoint policies."
  value       = aws_vpc.main.arn
}

output "availability_zones" {
  description = "Availability Zone names actually used by this module, in the order that subnets, NAT gateways and route tables were created."
  value       = local.availability_zones
}

# ---------------------------------------------------------------------------
# Subnet IDs
# ---------------------------------------------------------------------------

output "public_web_subnet_ids" {
  description = "IDs of the public web-tier subnets, AZ-ordered. Targets for the internet-facing ALB and the web-tier ASG."
  value       = aws_subnet.public_web[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of the private application-tier subnets, AZ-ordered. Targets for the internal ALB and the app-tier ASG."
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "IDs of the private database-tier subnets, AZ-ordered. Feed these to the database module's aws_db_subnet_group."
  value       = aws_subnet.private_db[*].id
}

# ---------------------------------------------------------------------------
# Subnet CIDRs -- consumed by the security module to scope SG rules
# ---------------------------------------------------------------------------

output "public_web_subnet_cidrs" {
  description = "CIDR blocks of the public web-tier subnets, AZ-ordered."
  value       = aws_subnet.public_web[*].cidr_block
}

output "private_app_subnet_cidrs" {
  description = "CIDR blocks of the private application-tier subnets, AZ-ordered."
  value       = aws_subnet.private_app[*].cidr_block
}

output "private_db_subnet_cidrs" {
  description = "CIDR blocks of the private database-tier subnets, AZ-ordered."
  value       = aws_subnet.private_db[*].cidr_block
}

# ---------------------------------------------------------------------------
# Gateways
# ---------------------------------------------------------------------------

output "internet_gateway_id" {
  description = "ID of the internet gateway. Only the public route table should ever reference this."
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways, AZ-ordered (one per AZ). Empty list when enable_nat_gateway is false."
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "Elastic IP addresses of the NAT gateways, AZ-ordered. These are the source addresses the app tier presents for outbound traffic, so they are what an external service would allow-list. Empty list when enable_nat_gateway is false."
  value       = aws_eip.nat[*].public_ip
}

output "nat_gateway_enabled" {
  description = "Whether NAT gateways were created. When false, the private application tier has no outbound internet path."
  value       = var.enable_nat_gateway
}

# ---------------------------------------------------------------------------
# Route tables -- exported for future VPC endpoint wiring
# ---------------------------------------------------------------------------
# A gateway endpoint (S3, DynamoDB) attaches to route tables; an interface
# endpoint attaches to subnets. Both sets of inputs are exported above/here.

output "public_route_table_id" {
  description = "ID of the shared public route table (0.0.0.0/0 -> internet gateway)."
  value       = aws_route_table.public.id
}

output "private_app_route_table_ids" {
  description = "IDs of the per-AZ private application route tables, AZ-ordered. Index N routes 0.0.0.0/0 to the NAT gateway in AZ N."
  value       = aws_route_table.private_app[*].id
}

output "private_db_route_table_id" {
  description = "ID of the shared private database route table. It carries only the implicit VPC-local route by design -- do not add a default route to it."
  value       = aws_route_table.private_db.id
}

output "private_route_table_ids" {
  description = "All private route table IDs (app tables first, then the db table). Convenient as the route_table_ids argument of an S3 gateway VPC endpoint."
  value       = concat(aws_route_table.private_app[*].id, [aws_route_table.private_db.id])
}
