#!/bin/bash

# ============================================================================
# Goal of this script is to setup prerequisite resources on AWS
# ============================================================================

# TODO
# - Create IAM role

if which terraform; then
  terraform version
else
  curl -Lo terraform.zip https://releases.hashicorp.com/terraform/1.5.6/terraform_1.5.6_linux_amd64.zip
  unzip terraform.zip
  chmod +x ./terraform
  mv ./terraform /usr/bin
fi

TF_PATH="./scripts/assets/aws-resources"
cp "$MICRO_ENV_CONFIG_FILE" "$TF_PATH"

terraform -chdir="$TF_PATH" init

# Terraform is stateful, so import the required resources if they exist
echo ""
echo "Importing existing resources if available..."
AWS_EC2_SG_NAME=$(readConfig ".aws.resources.ec2_security_group.name" "microenv-security-group")
AWS_EC2_SG_ID=$(aws ec2 describe-security-groups --filter "Name='group-name',Values=['$AWS_EC2_SG_NAME']" | jq -r ".SecurityGroups[0].GroupId")
if [[ "$AWS_EC2_SG_ID" != "null" ]]; then
  terraform -chdir="$TF_PATH" import aws_security_group.main "$AWS_EC2_SG_ID"
fi

AWS_EC2_LT_NAME=$(readConfig ".aws.resources.ec2_launch_template.name" "microenv-launcher")
AWS_EC2_LT_ID=$(aws ec2 describe-launch-templates --launch-template-names $AWS_EC2_LT_NAME | jq -r ".LaunchTemplates[0].LaunchTemplateId")
if [[ "$AWS_EC2_LT_ID" != "null" ]]; then
  terraform -chdir="$TF_PATH" import aws_launch_template.main "$AWS_EC2_LT_ID"
fi

terraform -chdir="$TF_PATH" plan -out=./plan.out

if [ -t 0 ]; then
  echo ""
  read -p "Press enter to apply the plan..."
  echo ""
fi

echo "Applying plan..."
terraform -chdir="$TF_PATH" apply "./plan.out"