# EC2 instance module for ecommerce application
resource "aws_instance" "main" {
  ami = local.ami_id
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  subnet_id = local.private_subnet_ids
  tags =merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-${var.component}"
      Terraform = "true"
  }
  )
}


#this is null resource
resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]

connection {
    type = "ssh"
    user = "ec2-user"
    password = "DevOps321"
    host = aws_instance.main.private_ip
}

# Provisioner to copy the file - terraform copies the file to the ec2 instance
provisioner "file" {
  source      = "bootstap.sh"       # Local file path
  destination = "/tmp/bootstap.sh"      # Remote path on EC2
}

provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/bootstap.sh",
      "sudo sh /tmp/bootstap.sh ${var.component}"
    ]
  }
}


# stopping the component instance 
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped" # Change to "running" to start the instance
  depends_on = [terraform_data.main]
}

# creating AMI from the component instance
resource "aws_ami_from_instance" "main" {
  name               = "${var.project_name}-${var.environment}-${var.component}-ami"
  source_instance_id = aws_instance.main.id
  depends_on = [aws_ec2_instance_state.main]
}


# target group for the instance
resource "aws_lb_target_group" "main" {
  name     = "${local.common_name_suffix}-${var.component}"
  port     = local.tg_port
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  deregistration_delay = 60 #waiting for 60 seconds before deregistering the instance from the target group
  health_check {
    path                = local.health_check_path
    port                = local.tg_port
    protocol            = "HTTP"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}


# creating launch template for the instance
resource "aws_launch_template" "main" {
  name = "${local.common_name_suffix}-${var.component}"
  image_id = aws_ami_from_instance.main.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t3.micro"

  vpc_security_group_ids = [local.sg_id]
  update_default_version = true


  tag_specifications {
  resource_type = "instance"

  tags = merge(local.common_tags, {
    Name = "${local.common_name_suffix}-${var.component}"
  })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.common_tags, {
      Name = "${local.common_name_suffix}-${var.component}"
    })
  }
}


# auto scaling group for the catalogue instance
resource "aws_autoscaling_group" "main" {
  name                      = "${local.common_name_suffix}-${var.component}"
  max_size                  = 10
  min_size                  = 1
  health_check_grace_period = 100
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete               = false
  launch_template {
    id      = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }

  vpc_zone_identifier       = [local.private_subnet_ids]
  target_group_arns         = [aws_lb_target_group.main.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  timeouts {
    delete = "15m"
  }

  
}

resource "aws_autoscaling_policy" "main" {
  name                   = "${local.common_name_suffix}-${var.component}"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}


resource "aws_lb_listener_rule" "main" {
  listener_arn = local.listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [local.host_context]
    }
  }
}

resource "terraform_data" "main_local" {
  triggers_replace = [
    aws_instance.main.id
  ]

depends_on = [aws_autoscaling_policy.main]

provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
}