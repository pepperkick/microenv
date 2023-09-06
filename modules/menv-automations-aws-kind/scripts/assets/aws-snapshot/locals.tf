locals {
  config = yamldecode(file("${path.module}/config.yaml"))
  aws = lookup(local.config, "aws", "")
  resources = lookup(local.aws, "snapshot", "")
  snapshot = lookup(local.resources, "name", "")
  r_infra = lookup(local.resources, "infra", "")
  r_infra_instance_types = lookup(local.r_infra, "instance_types", "")
  r_recipe = lookup(local.resources, "recipe", "")
  r_component = lookup(local.resources, "component", "")
  r_distribution = lookup(local.resources, "distribution", "")
}
