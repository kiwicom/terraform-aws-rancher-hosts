# General
variable "aws_account_id" {
  description = "The AWS account id"
  type        = string
}

variable "aws_remote_state_bucket" {
  description = "Remote state bucket name"
  type        = string
}

variable "aws_remote_state_key" {
  description = "Remote state file path"
  type        = string
}

variable "aws_remote_state_arn" {
  description = "Remote state Role ARN"
  type        = string
}

variable "resources_prefix" {
  description = "Creates a unique name beginning with the specified prefix"
}

variable "project_url" {
  description = "The url of project repository, used in resource tag"
  default     = ""
}

# Launch configuration
variable "image_id" {
  description = "The EC2 image ID to launch"
}

variable "instance_type" {
  description = "The size of instance to launch"
}

variable "rancher_workspace" {
  description = "Which remote state should TF get env ID/registration_url from"
}

variable "rancher_env_name" {
  description = "The name of the Rancher environment"
}

variable "create_failover_asg" {
  description = "true/false, whether create failover autoscaling group or not, default false"
  default     = "false"
}

variable "additional_lc_security_groups" {
  description = "A list of additional security group IDs to assign to the launch configuration"
  type        = list(string)
  default     = [] // optional
}

variable "additional_user_data" {
  description = "Addtional user data to attach to default rancher host user_data"
  default     = "" // optional
}

variable "ebs_block_device_volume_size" {
  description = "Volume size of attached EBS"
  default     = 30
}

# Autoscaling group
variable "iam_instance_profile" {
  description = "The ARN of instance profile, if you want to use other than default (tf_rancherhost)"
  default     = ""
}

variable "max_size" {
  description = "The maximum size of the auto scale group"
}

variable "min_size" {
  description = "The minimum size of the auto scale group"
}

variable "asg_subnets" {
  description = "A list of subnet IDs to launch resources in"
  type        = list(string)
}

variable "elb_subnets" {
  description = "I am sad"
  type        = list(string)
  default     = []
}

variable "elb_cloudflare_only" {
  description = "Allow ingress from CloudFlare servers only"
  default     = false
}

variable "load_balancers" {
  description = "A list of elastic load balancer names to add to the autoscaling group names"
  type        = list(string)
  default     = [] // optional
}

variable "target_group_arns" {
  description = "A list of aws_alb_target_group ARNs, for use with Application Load Balancing"
  type        = list(string)
  default     = [] // optional
}

variable "tags" {
  description = "A list of additional tag blocks. Each element should have keys named key, value, and propagate_at_launch."
  type        = list(string)
  default     = [] // optional
}

# ELBs
variable "create_default_elb" {
  description = "Creates ELB with default values - check README for more info"
  default     = true
}

variable "create_default_elb_i" {
  description = "Creates internal ELB with default values - check README for more info"
  default     = false
}

variable "create_default_elb_ws" {
  description = "Creates WebSockets ELB with default values - check README for more info"
  default     = false
}

variable "ssl_certificate_arn" {
  description = "Attach SSL certificate to default ELBs"
  default     = ""
}
