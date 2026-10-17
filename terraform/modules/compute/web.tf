# =============================================================================
# Web tier -- Next.js, public subnets, public ALB target
# =============================================================================

locals {
  web_user_data = templatefile(
    "${path.module}/templates/web_user_data.sh.tpl",
    {
      app_repo_url          = var.app_repo_url
      internal_alb_dns_name = var.internal_alb_dns_name
      internal_alb_port     = var.internal_alb_port
    }
  )
}

resource "aws_launch_template" "web" {
  name          = "${var.project_name}-${var.environment}-web-lt"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.web_instance_type

  # aws_launch_template.user_data must be pre-encoded -- unlike aws_instance,
  # this resource does not base64-encode it for you.
  user_data = base64encode(local.web_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  # The web tier is the one place in the architecture with a legitimate,
  # scoped public IP (CLAUDE.md section 3: "web tier instances run in public
  # subnets and may hold public IPs for outbound access"). subnet_id is
  # deliberately omitted here -- the web-tier ASG's vpc_zone_identifier
  # spreads instances across var.public_subnet_ids, and Terraform/AWS resolve
  # the subnet for each launched instance from the ASG at launch time.
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.web_security_group_id]
    device_index                = 0
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-${var.environment}-web"
        Tier = "web"
      }
    )
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-web-lt"
    }
  )
}

resource "aws_autoscaling_group" "web" {
  name = "${var.project_name}-${var.environment}-web-asg"

  # One instance per public subnet / AZ, matching CLAUDE.md section 3's
  # "at least 2 Availability Zones" requirement for the web tier.
  min_size         = length(var.public_subnet_ids)
  max_size         = length(var.public_subnet_ids)
  desired_capacity = length(var.public_subnet_ids)

  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = [var.web_target_group_arn]

  # ELB health checks (not just EC2 status checks) so a web instance that
  # boots but fails the ALB's health check gets replaced.
  health_check_type = "ELB"

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(
      var.tags,
      {
        Name = "${var.project_name}-${var.environment}-web"
        Tier = "web"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
