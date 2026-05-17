# ── IAM Role for EC2 Instances ────────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── Launch Template ────────────────────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile { arn = aws_iam_instance_profile.ec2.arn }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }

  monitoring { enabled = true }

  # Install Docker + pull & run the app image on boot
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex
    yum update -y
    yum install -y docker amazon-cloudwatch-agent
    systemctl enable --now docker

    # Pull latest app image from ECR (update with your ECR URI)
    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin \
      ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com

    docker pull ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/cloudsentinel-app:latest

    docker run -d \
      --name cloudsentinel-app \
      --restart unless-stopped \
      -p 3000:3000 \
      -e NODE_ENV=production \
      ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/cloudsentinel-app:latest

    # Start CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s -c ssm:${aws_ssm_parameter.cw_config.name}
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-app"
    }
  }

  lifecycle { create_before_destroy = true }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.private[*].id

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]
  health_check_type = "ELB"
  health_check_grace_period = 120

  # Rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }
}

# ── Target Tracking Scaling Policy (CPU) ──────────────────────────────────────
resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "${var.project_name}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = var.scale_out_cpu_threshold
    disable_scale_in = false
  }
}

# ── Step Scaling Policy (ALB Request Count per Target) ────────────────────────
resource "aws_autoscaling_policy" "request_count" {
  name                   = "${var.project_name}-request-count"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000   # requests per target per minute
  }
}

# ── Scheduled Scaling (business hours) ───────────────────────────────────────
resource "aws_autoscaling_schedule" "scale_up_morning" {
  scheduled_action_name  = "scale-up-morning"
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
  desired_capacity       = 3
  recurrence             = "0 3 * * MON-FRI"   # 08:30 IST (UTC+5:30)
  time_zone              = "Asia/Kolkata"
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_autoscaling_schedule" "scale_down_night" {
  scheduled_action_name  = "scale-down-night"
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
  desired_capacity       = var.asg_desired_capacity
  recurrence             = "30 14 * * MON-FRI"  # 20:00 IST
  time_zone              = "Asia/Kolkata"
  autoscaling_group_name = aws_autoscaling_group.app.name
}

# ── CloudWatch Agent SSM Config ───────────────────────────────────────────────
resource "aws_ssm_parameter" "cw_config" {
  name  = "/${var.project_name}/cloudwatch-agent-config"
  type  = "String"
  value = jsonencode({
    agent = { metrics_collection_interval = 60 }
    metrics = {
      namespace = "CloudSentinel/EC2"
      metrics_collected = {
        cpu    = { measurement = ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"], metrics_collection_interval = 60 }
        mem    = { measurement = ["mem_used_percent"], metrics_collection_interval = 60 }
        disk   = { measurement = ["used_percent"], resources = ["/"] }
        netstat = { measurement = ["tcp_established", "tcp_time_wait"] }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [{
            file_path        = "/var/log/cloudsentinel/*.log"
            log_group_name   = "/${var.project_name}/app"
            log_stream_name  = "{instance_id}"
            timestamp_format = "%Y-%m-%dT%H:%M:%S"
          }]
        }
      }
    }
  })
}
