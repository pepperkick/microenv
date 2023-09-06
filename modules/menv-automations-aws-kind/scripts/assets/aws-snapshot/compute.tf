data "aws_iam_instance_profile" "selected" {
  name = lookup(local.r_infra, "iam_role", "microenv-role")
}

data "aws_security_group" "selected" {
  id = lookup(local.r_infra, "security_group", "")
}

data "aws_subnet" "selected" {
  id = lookup(local.r_infra, "subnet", "")
}

data "aws_s3_bucket" "selected" {
  bucket = lookup(local.r_infra, "logs_bucket", "automations")
}

data "aws_ami" "image" {
  owners = [lookup(local.r_recipe, "base_image_owner", "031087784557")]
  filter {
    name   = "image-id"
    values = [lookup(local.r_recipe, "base_image_id", "ami-0c05b7e2855657f6b")]
  }
}

resource "aws_imagebuilder_image_pipeline" "main" {
  name                             = "microenv-${local.snapshot}-image-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.main.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.main.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.main.arn
}

resource "aws_imagebuilder_infrastructure_configuration" "main" {
  name                          = "microenv-${local.snapshot}-infra-config"
  description                   = "MicroEnv ${local.snapshot}"
  instance_profile_name         = data.aws_iam_instance_profile.selected.name
  instance_types                = local.r_infra_instance_types
  security_group_ids            = [data.aws_security_group.selected.id]
  subnet_id                     = data.aws_subnet.selected.id
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = data.aws_s3_bucket.selected.bucket
      s3_key_prefix  = lookup(local.r_infra, "logs_prefix", "build/microenv/snapshot/logs")
    }
  }
}

resource "aws_imagebuilder_image_recipe" "main" {
  name         = "microenv-${local.snapshot}-image-recipe"
  parent_image = data.aws_ami.image.arn
  version      = "1.0.0"

  block_device_mapping {
    device_name = data.aws_ami.image.root_device_name

    ebs {
      delete_on_termination = true
      volume_size           = lookup(local.r_recipe, "storage_size", 150)
      volume_type           = "gp3"
    }
  }

  component {
    component_arn = aws_imagebuilder_component.main-build.arn

    parameter {
      name  = "Domain"
      value = lookup(local.r_component, "domain", "abc.xyz")
    }

    parameter {
      name  = "Build"
      value = lookup(local.r_component, "build_file", "kind")
    }

    parameter {
      name  = "Config"
      value = lookup(local.r_component, "config_file", "kind")
    }
  }
}

resource "aws_imagebuilder_component" "main-build" {
  name     = "microenv-${local.snapshot}-build-component"
  platform = "Linux"
  version  = "1.0.0"
  data = yamlencode({
    parameters = [{
      Domain = {
        type = "string"
        default = lookup(local.r_component, "domain", "abc.xyz")
        description = "The domain to use for the instance"
      }
      Build = {
        type = "string"
        default = lookup(local.r_component, "build_file", "kind")
        description = "The microenv build file to use"
      }
      Config = {
        type = "string"
        default = lookup(local.r_component, "config_file", "kind")
        description = "The microenv config file to use"
      }
    }]
    phases = [{
      name = "build"
      schemaVersion = 1.0
      steps = [{
        name   = "FetchConfigs"
        action = "S3Download"
        inputs = [{
          source = "s3://${lookup(local.r_component, "bucket", "automations")}/${lookup(local.r_component, "prefix", "resources/microenv/snapshot/configs")}/build.{{ Build }}.yaml"
          destination = "/home/ec2-user/microenv/build.yaml"
          overwrite = true
        }, {
          source = "s3://${lookup(local.r_component, "bucket", "automations")}/${lookup(local.r_component, "prefix", "resources/microenv/snapshot/configs")}/config.{{ Config }}.yaml"
          destination = "/home/ec2-user/microenv/config.yaml"
          overwrite = true
        }]
      }, {
        name   = "Execute"
        action = "ExecuteBash"
        inputs = {
          commands = [
            <<EOF
            cd /home/ec2-user/microenv
            curl -Lo ./build.sh https://raw.githubusercontent.com/pepperkick/microenv/main/build.sh
            chmod +x ./build.sh
            ./build.sh -c ./build.yaml
            unzip ./menv.zip
            ./menv.sh create --config ./config.yaml
            EOF
          ]
        }
      }]
    }]
  })
}

resource "aws_imagebuilder_distribution_configuration" "main" {
  name = "microenv-${local.snapshot}-distribution"

  distribution {
    region = lookup(local.aws, "region", "us-west-2")

    launch_template_configuration {
      launch_template_id = lookup(local.r_distribution, "launch_template", "")
      default = true
    }
  }
}