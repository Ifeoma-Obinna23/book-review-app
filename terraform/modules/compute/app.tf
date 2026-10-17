# =============================================================================
# App tier -- Node.js/Express, private app subnets, internal ALB target only
# =============================================================================

locals {
  app_user_data = templatefile(
    "${path.module}/templates/app_user_data.sh.tpl",
    {
      app_repo_url        = var.app_repo_url
      db_secret_name      = var.db_secret_name
      app_allowed_origins = var.app_allowed_origins
      aws_region          = var.aws_region
    }
  )
}

resource "aws_launch_template" "app" {
  name          = "${var.project_name}-${var.environment}-app-lt"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.app_instance_type

  # aws_launch_template.user_data must be pre-encoded -- unlike aws_instance,
  # this resource does not base64-encode it for you.
  user_data = base64encode(local.app_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  # CLAUDE.md section 3: "No compute resource in the app or db tier may have
  # a public IP." associate_public_ip_address is explicitly false, and
  # subnet_id is omitted so the app-tier ASG's vpc_zone_identifier
  # (var.private_app_subnet_ids) controls placement across both private app
  # subnets.
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.app_security_group_id]
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
        Name = "${var.project_name}-${var.environment}-app"
        Tier = "app"
      }
    )
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-app-lt"
    }
  )
}

resource "aws_autoscaling_group" "app" {
  name = "${var.project_name}-${var.environment}-app-asg"

  # One instance per private app subnet / AZ, matching CLAUDE.md section 3's
  # "at least 2 Availability Zones" requirement for the app tier.
  min_size         = length(var.private_app_subnet_ids)
  max_size         = length(var.private_app_subnet_ids)
  desired_capacity = length(var.private_app_subnet_ids)

  vpc_zone_identifier = var.private_app_subnet_ids
  target_group_arns   = [var.app_target_group_arn]

  # ELB health checks against the internal ALB's app target group (port
  # 3001), not just EC2 status checks.
  health_check_type = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(
      var.tags,
      {
        Name = "${var.project_name}-${var.environment}-app"
        Tier = "app"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
