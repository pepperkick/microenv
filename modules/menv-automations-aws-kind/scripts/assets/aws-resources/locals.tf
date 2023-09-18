locals {
  config = yamldecode(file("${path.module}/config.yaml"))
  aws = lookup(local.config, "aws", "")
  terraform = lookup(local.config, "terraform", "")
  resources = lookup(local.aws, "resources", "")
  r_vpc = lookup(local.resources, "vpc", "")
  r_ec2_ami = lookup(local.resources, "ec2_ami", "")
  r_ec2_security_group = lookup(local.resources, "ec2_security_group", "")
  r_ec2_launch_template = lookup(local.resources, "ec2_launch_template", "")
}