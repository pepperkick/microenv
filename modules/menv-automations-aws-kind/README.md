# MicroEnv Automations AWS KIND

Provides automations to create KIND mircoenv on AWS

## Requirements

- aws cli
- terraform

## Scripts

### aws-setup

Deploy all the prerequisites for AWS.

### aws-create

Create a new EC2 instance and deploy KIND on it.

### aws-destroy

Destroy the EC2 instance created for KIND.

## Config

```yaml
# Configure value for AWS
aws:
  region: us-west-2

  domain_zone: kind.xyz

  ssm:
    output:
      bucket: automations
      path: "build/logs"

  build:
    bucket: automations
    path: "build/microenv/packages"

  menv:
    bucket: automations
    path: "build/microenv/distributions"
    distribution: "menv-kind-helmfile"

  # Configure the AWS resources that will be created.
  # If a value is empty then the script will try to autofill it.
  # If `id` key is present then that takes precedence over all the other config and it must exist
  resources:
    # VPC
    vpc:
      id: ""
      subnet: ""

    # EC2 Security Group
    ec2_security_group:
      name: microenv-security-group
      ingress_cidr: 10.10.10.10/32

    # EC2 AMI
    ec2_ami:
      # Tested AMIs
      # - RHEL 8
      id: ""
      owner: ""

    # EC2 Launch Template
    ec2_launch_template:
      name: microenv-launcher
      instance_type: m5.2xlarge
      storage_size: 150
```
