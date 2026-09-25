# =============================================================================
# Compute module -- shared AMI lookup and shared IAM role/instance profile
# =============================================================================
#
# Web-tier and app-tier resources live in web.tf and app.tf respectively.
# Both tiers share one AMI data source and one IAM role/instance profile, so
# those go here.
#
# This module creates no security groups (only the security module may,
# per CLAUDE.md section 5) and no SSH key pair -- access to every instance in
# this module is via SSM Session Manager, using the SSM Agent already baked
# into the Amazon Linux 2023 AMI plus the AmazonSSMManagedInstanceCore policy
# attached below. The single SSH exception in the architecture (admin_cidr,
# port 22, web tier only) is a security-group-level allowance already
# enforced by the security module; it does not require a key pair resource
# here because operators are expected to use SSM anyway -- but nothing in
# this module block that path if the caller has their own key management.
# =============================================================================

# -----------------------------------------------------------------------------
# AMI -- most recent Amazon Linux 2023, x86_64
# -----------------------------------------------------------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# IAM -- one role/instance profile shared by web and app tiers
# -----------------------------------------------------------------------------
# A single shared role (rather than one per tier) is deliberate: both tiers
# need exactly the same two things today -- SSM Session Manager access and
# read access to the same future Secrets Manager namespace -- so a second
# role would just be a duplicate with no least-privilege benefit. If the two
# tiers' permissions ever diverge (e.g. only the app tier should read DB
# secrets), split this into web/app-specific roles at that point rather than
# widening one role to cover both.

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.project_name}-${var.environment}-compute-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-compute-role"
    }
  )
}

# Grants SSM Session Manager connectivity (and basic SSM inventory/patch
# management) -- this is the entire administrative access path for the app
# tier, and the primary one for the web tier alongside its single SSH
# exception.
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped to a single secret ARN pattern (default: this project/environment's
# own secrets namespace) rather than "*", and to GetSecretValue only -- no
# List/Describe/Put/Delete. Not consumed by any resource in this module yet;
# it exists so the database module can later hand the app tier real
# credentials via Secrets Manager instead of the placeholder .env values in
# app_user_data.sh.tpl, without a second IAM change.
data "aws_iam_policy_document" "secrets_manager_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secrets_manager_arn_pattern]
  }
}

resource "aws_iam_role_policy" "secrets_manager_read" {
  name   = "${var.project_name}-${var.environment}-secrets-read"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.secrets_manager_read.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project_name}-${var.environment}-compute-profile"
  role = aws_iam_role.instance.name

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-compute-profile"
    }
  )
}
