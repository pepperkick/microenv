data "aws_vpc" "main" {
  id = lookup(local.r_vpc, "id", "")
}

data "aws_subnet" "main" {
  id = lookup(local.r_vpc, "subnet", "")
}

data "aws_ami" "image" {
  owners = [lookup(local.r_ec2_ami, "ami.owner", "031087784557")]
  filter {
    name   = "image-id"
    values = [lookup(local.r_ec2_ami, "id", "ami-0c05b7e2855657f6b")]
  }
}

resource "aws_security_group" "main" {
  name = lookup(local.r_ec2_security_group, "name", "microenv-security-group")
  description = "Security Group for MicroEnvs"
  vpc_id = data.aws_vpc.main.id

  ingress {
    description = "Allow HTTPS Port"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [lookup(local.r_ec2_security_group, "ingress_cidr", "123.123.123.123/32")]
  }

  ingress {
    description = "Allow Kubernetes Port"
    from_port   = 55555
    to_port     = 55555
    protocol    = "tcp"
    cidr_blocks = [lookup(local.r_ec2_security_group, "ingress_cidr", "123.123.123.123/32")]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "main" {
  name = lookup(local.r_ec2_launch_template, "name", "microenv-launcher")
  instance_type = lookup(local.r_ec2_launch_template, "instance_type", "m5.2xlarge")
  image_id = data.aws_ami.image.id
  instance_initiated_shutdown_behavior = "terminate"
  vpc_security_group_ids = [aws_security_group.main.id]

  block_device_mappings {
    device_name = data.aws_ami.image.root_device_name
    ebs {
      delete_on_termination = true
      volume_size = lookup(local.r_ec2_launch_template, "storage_size", 150)
      volume_type = "gp3"
      snapshot_id = data.aws_ami.image.root_snapshot_id
    }
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination = true
    security_groups  = [aws_security_group.main.id]
    subnet_id = data.aws_subnet.main.id
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      microenv = "true"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      microenv = "true"
    }
  }
}