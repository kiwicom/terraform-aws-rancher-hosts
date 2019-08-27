// get correct rancher - dev/search/prod
data "terraform_remote_state" "rancher" {
  backend   = "s3"
  workspace = var.rancher_workspace

  config = {
    bucket               = var.aws_remote_state_bucket
    key                  = var.aws_remote_state_key
    region               = "eu-west-1"
    dynamodb_table       = "terraform_locking"
    workspace_key_prefix = "workspace"
    role_arn             = "arn:aws:iam::${var.aws_account_id}:role/${var.aws_remote_state_arn}"
  }
}

// used only if create_failover_asg = true
data "terraform_remote_state" "rancher_failover" {
  backend   = "s3"
  workspace = "failover"

  config = {
    bucket               = var.aws_remote_state_bucket
    key                  = var.aws_remote_state_key
    region               = "eu-west-1"
    dynamodb_table       = "terraform_locking"
    workspace_key_prefix = "workspace"
    role_arn             = "arn:aws:iam::${var.aws_account_id}:role/${var.aws_remote_state_arn}"
  }
}

// used only for cloudflare_ip_ranges data source
provider "cloudflare" {
  email = "frozen@hozen.com"
  token = "troll"
}
