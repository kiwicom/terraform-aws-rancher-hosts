output "elb_external" {
  value = {
    "id"       = concat(aws_elb.external.*.id, [""])[0]
    "dns_name" = concat(aws_elb.external.*.dns_name, [""])[0]
  }
}

output "elb_internal" {
  value = {
    "id"       = concat(aws_elb.internal.*.id, [""])[0]
    "dns_name" = concat(aws_elb.internal.*.dns_name, [""])[0]
  }
}

output "elb_websockets" {
  value = {
    "id"       = concat(aws_elb.websockets.*.id, [""])[0]
    "dns_name" = concat(aws_elb.websockets.*.dns_name, [""])[0]
  }
}

output "asg_name" {
  value = aws_autoscaling_group.this.name
}

output "failover_asg_name" {
  value = ""
}
