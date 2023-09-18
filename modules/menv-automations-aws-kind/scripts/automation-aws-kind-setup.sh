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

TF_BACKEND_REGION=$(readConfig ".aws.region" "us-west-2")
TF_BACKEND_BUCKET=$(readConfig ".terraform.s3_backend.bucket" "automations")
TF_BACKEND_PATH=$(readConfig ".terraform.s3_backend.path" "build/microenv/terraform/states")
TF_BACKEND_KEY="${TF_BACKEND_PATH}/deployment.tfstate"

echo "bucket = \"${TF_BACKEND_BUCKET}\"" > "$TF_PATH/backend.tfvars"
echo "key = \"${TF_BACKEND_KEY}\"" >> "$TF_PATH/backend.tfvars"
echo "region = \"${TF_BACKEND_REGION}\"" >> "$TF_PATH/backend.tfvars"

terraform -chdir="$TF_PATH" init -backend-config backend.

echo "Planning..."
terraform -chdir="$TF_PATH" plan -out=./plan.out

if [ -t 0 ]; then
  echo ""
  read -p "Press enter to apply the plan..."
  echo ""
fi

echo "Applying plan..."
terraform -chdir="$TF_PATH" apply "./plan.out"