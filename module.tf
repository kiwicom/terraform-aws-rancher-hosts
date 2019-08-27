data "aws_caller_identity" "this" {
}

data "aws_iam_account_alias" "this" {
}

data "cloudflare_ip_ranges" "cloudflare" {
}

// Locals - express it just once, use multiple times
locals {
  public_elb_ingress_cidr_blocks = split(
    ",",
    var.elb_cloudflare_only ? join(",", data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks) : "0.0.0.0/0",
  )
}

data "template_file" "user_data_rancher_host" {
  template = file("${path.module}/userdata/r-host.sh.template")

  vars = {
    registration_url     = data.terraform_remote_state.rancher.outputs.registration_url[var.rancher_env_name]
    env_name             = var.resources_prefix
    additional_user_data = var.additional_user_data
    aws_account_id       = data.aws_caller_identity.this.account_id
    aws_account_alias    = data.aws_iam_account_alias.this.account_alias
  }
}

// failover ASG
data "template_file" "user_data_rancher_host_failover" {
  count    = var.rancher_workspace == "prod" ? 1 : 0
  template = file("${path.module}/userdata/r-host.sh.template")

  vars = {
    registration_url     = data.terraform_remote_state.rancher_failover.outputs.registration_url[var.rancher_env_name]
    env_name             = "${var.resources_prefix}-failover"
    additional_user_data = var.additional_user_data
    aws_account_id       = data.aws_caller_identity.this.account_id
    aws_account_alias    = data.aws_iam_account_alias.this.account_alias
  }
}

data "aws_subnet" "this" {
  id = var.asg_subnets[0]
}

data "aws_vpc" "this" {
  id = data.aws_subnet.this.vpc_id
}

resource "aws_security_group" "lc" {
  name        = "${var.resources_prefix}-launch_configuration"
  description = "Allow ALL inbound traffic to instances from VPCs"
  vpc_id      = data.aws_subnet.this.vpc_id

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resources_prefix}-lc"
  }
}

resource "aws_launch_configuration" "r_host" {
  name_prefix          = "${var.resources_prefix}-"
  image_id             = var.image_id
  instance_type        = var.instance_type
  iam_instance_profile = coalesce(
    var.iam_instance_profile,
    "arn:aws:iam::${data.aws_caller_identity.this.account_id}:instance-profile/tf_rancherhost",
  )
  user_data            = data.template_file.user_data_rancher_host.rendered

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp2"
    volume_size           = var.ebs_block_device_volume_size
    delete_on_termination = true
  }

  security_groups = concat([aws_security_group.lc.id], var.additional_lc_security_groups)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name_prefix          = "${var.resources_prefix}-"
  launch_configuration = aws_launch_configuration.r_host.name
  min_size             = var.min_size
  max_size             = var.max_size

  vpc_zone_identifier = var.asg_subnets

  load_balancers = compact(
    concat(
      aws_elb.external.*.id,
      aws_elb.internal.*.id,
      var.load_balancers,
    ),
  )

  health_check_grace_period = 300
  health_check_type         = "EC2"

  target_group_arns    = var.target_group_arns
  default_cooldown     = 300
  termination_policies = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = var.resources_prefix
    propagate_at_launch = true
  }

  tag {
    key                 = "project"
    value               = var.project_url
    propagate_at_launch = true
  }

  tag {
    key                 = "rancher"
    value               = format(
    replace(
    data.terraform_remote_state.rancher.outputs.registration_url[var.rancher_env_name],
    "/(.com).*$/",
    ".com/%s",
    ),
    "env/${data.terraform_remote_state.rancher.outputs.stack_id[var.rancher_env_name]}",
    )
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

// failover ASG, created only if create_failover_asg = true
resource "aws_launch_configuration" "r_host_failover" {
  count = var.create_failover_asg == "true" || var.create_failover_asg ? 1 : 0

  name_prefix          = "${var.resources_prefix}-failover-"
  image_id             = var.image_id
  instance_type        = var.instance_type
  iam_instance_profile = aws_launch_configuration.r_host.iam_instance_profile
  user_data            = data.template_file.user_data_rancher_host_failover[0].rendered

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp2"
    volume_size           = var.ebs_block_device_volume_size
    delete_on_termination = true
  }

  security_groups = aws_launch_configuration.r_host.security_groups

  lifecycle {
    create_before_destroy = true
  }
}

// failover ASG, created only if create_failover_asg = true
resource "aws_autoscaling_group" "this_failover" {
  count = var.create_failover_asg == "true" || var.create_failover_asg ? 1 : 0

  name_prefix          = "${var.resources_prefix}-failover-"
  launch_configuration = aws_launch_configuration.r_host_failover[0].name
  min_size             = "0" // TODO correct? desired manually?
  max_size             = var.max_size

  vpc_zone_identifier = aws_autoscaling_group.this.vpc_zone_identifier

  load_balancers = compact(
    concat(
      aws_elb.external.*.id,
      aws_elb.internal.*.id,
      var.load_balancers,
    ),
  )

  health_check_grace_period = aws_autoscaling_group.this.health_check_grace_period
  health_check_type         = aws_autoscaling_group.this.health_check_type

  target_group_arns    = var.target_group_arns
  default_cooldown     = aws_autoscaling_group.this.default_cooldown
  termination_policies = aws_autoscaling_group.this.termination_policies


  tag {
    key                 = "Name"
    value               = "${var.resources_prefix}-failover"
    propagate_at_launch = true
  }

  tag {
    key                 = "project"
    value               = var.project_url
    propagate_at_launch = true
  }

  tag {
    key                 = "rancher"
    value               = format(
    replace(
    data.terraform_remote_state.rancher.outputs.registration_url[var.rancher_env_name],
    "/(.com).*$/",
    ".com/%s",
    ),
    "env/${data.terraform_remote_state.rancher.outputs.stack_id[var.rancher_env_name]}",
    )
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_security_group" "elb" {
  count = var.create_default_elb ? 1 : 0

  name        = "${var.resources_prefix}-elb"
  description = "Allow public inbound traffic to ELB ports"
  vpc_id      = data.aws_subnet.this.vpc_id

  ingress {
    from_port   = 80
    protocol    = "TCP"
    to_port     = 80
    cidr_blocks = local.public_elb_ingress_cidr_blocks
  }

  ingress {
    from_port   = 443
    protocol    = "TCP"
    to_port     = 443
    cidr_blocks = local.public_elb_ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resources_prefix}-elb"
  }
}

resource "aws_elb" "external" {
  count = var.create_default_elb ? 1 : 0

  name            = var.resources_prefix
  security_groups = [aws_security_group.elb[0].id]
  subnets         = var.elb_subnets
  internal        = false

  listener {
    instance_port     = 44380
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = var.ssl_certificate_arn == "" ? "http" : "https"
    ssl_certificate_id = var.ssl_certificate_arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 4
    target              = "TCP:80"
    interval            = 5
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 300
  connection_draining         = true
  connection_draining_timeout = 300

  tags = {
    Name    = var.resources_prefix
    project = var.project_url
  }
}

resource "aws_security_group" "elb_i" {
  count = var.create_default_elb_i ? 1 : 0

  name        = "${var.resources_prefix}-elb-i"
  description = "Allow ALL inbound traffic to ELB from VPCs"
  vpc_id      = data.aws_subnet.this.vpc_id

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resources_prefix}-elb-i"
  }
}

resource "aws_elb" "internal" {
  count = var.create_default_elb_i ? 1 : 0

  name            = "${var.resources_prefix}-i"
  security_groups = [aws_security_group.elb_i[0].id]
  subnets         = var.elb_subnets
  internal        = true

  listener {
    instance_port     = 44380
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = var.ssl_certificate_arn == "" ? "http" : "https"
    ssl_certificate_id = var.ssl_certificate_arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 4
    target              = "TCP:80"
    interval            = 5
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 300
  connection_draining         = true
  connection_draining_timeout = 300

  tags = {
    Name    = "${var.resources_prefix}-i"
    project = var.project_url
  }
}

resource "aws_security_group" "elb_ws" {
  count = var.create_default_elb_ws ? 1 : 0

  name        = "${var.resources_prefix}-elb-ws"
  description = "Allow public inbound traffic to ELB ports"
  vpc_id      = data.aws_subnet.this.vpc_id

  ingress {
    from_port   = 80
    protocol    = "TCP"
    to_port     = 80
    cidr_blocks = local.public_elb_ingress_cidr_blocks
  }

  ingress {
    from_port   = 443
    protocol    = "TCP"
    to_port     = 443
    cidr_blocks = local.public_elb_ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resources_prefix}-elb-ws"
  }
}

resource "aws_elb" "websockets" {
  count = var.create_default_elb_ws ? 1 : 0

  name            = "${var.resources_prefix}-ws"
  security_groups = [aws_security_group.elb_ws[0].id]
  subnets         = var.elb_subnets
  internal        = false

  listener {
    instance_port     = 44380
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = var.ssl_certificate_arn == "" ? "tcp" : "ssl"
    ssl_certificate_id = var.ssl_certificate_arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 4
    target              = "TCP:80"
    interval            = 5
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 300
  connection_draining         = true
  connection_draining_timeout = 300

  tags = {
    Name    = "${var.resources_prefix}-ws"
    project = var.project_url
  }
}
