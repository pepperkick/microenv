terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.19.0"
    }
  }
}

provider "aws" {
  region = lookup(local.aws, "region", "us-west-2")

  default_tags {
    tags = {
      microenv = "true"
    }
  }
}