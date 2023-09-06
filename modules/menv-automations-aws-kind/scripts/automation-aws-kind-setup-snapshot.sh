#!/bin/bash

# ============================================================================
# Goal of this script is to setup resources for creating snapshot
# ============================================================================

if which terraform; then
  terraform version
else
  curl -Lo terraform.zip https://releases.hashicorp.com/terraform/1.5.6/terraform_1.5.6_linux_amd64.zip
  unzip terraform.zip
  chmod +x ./terraform
  mv ./terraform /usr/bin
fi

TF_PATH="./scripts/assets/aws-snapshot"
cp "$MICRO_ENV_CONFIG_FILE" "$TF_PATH"

terraform -chdir="$TF_PATH" init

# Terraform is stateful, so import the required resources if they exist
echo ""
echo "Importing existing resources if available..."
AWS_SNAPSHOT=$(readConfig ".aws.snapshot.name" "microenv-kind")

AWS_IB_PL_NAME="microenv-${AWS_SNAPSHOT}-pipeline"
AWS_IB_PL_ID=$(aws imagebuilder list-image-pipelines --filters "name='name',values=['$AWS_IB_PL_NAME']" | jq -r ".imagePipelineList[0].arn")
if [[ "$AWS_EC2_SG_ID" != "null" ]]; then
  terraform -chdir="$TF_PATH" import aws_imagebuilder_image_pipeline.main "$AWS_IB_PL_ID"
fi

AWS_IB_IC_NAME="microenv-${AWS_SNAPSHOT}-infra-config"
AWS_IB_IC_ID=$(aws imagebuilder list-infrastructure-configurations --filters "name='name',values=['$AWS_IB_IC_NAME']" | jq -r ".infrastructureConfigurationSummaryList[0].arn")
if [[ "$AWS_IB_IC_ID" != "null" ]]; then
  terraform -chdir="$TF_PATH" import aws_imagebuilder_infrastructure_configuration.main "$AWS_IB_IC_ID"
fi

AWS_IB_IR_NAME="microenv-${AWS_SNAPSHOT}-image-recipe"
AWS_IB_IR_ID=$(aws imagebuilder list-image-recipes --filters "name='name',values=['$AWS_IB_IR_NAME']" | jq -r ".imageRecipeSummaryList[0].arn")
if [[ "$AWS_IB_IR_ID" != "null" ]]; then
  terraform -chdir="$TF_PATH" import aws_imagebuilder_image_recipe.main "$AWS_IB_IR_ID"
fi

AWS_IB_BUILD_COMP_NAME="microenv-${AWS_SNAPSHOT}-build-component"
AWS_IB_BUILD_COMP_ID=$(aws imagebuilder list-components --filters "name='name',values=['$AWS_IB_BUILD_COMP_NAME']" | jq -r ".componentVersionList[0].arn")
if [[ "$AWS_IB_BUILD_COMP_ID" != "null" ]]; then
  terraform -chdir="$TF_PATH" import aws_imagebuilder_component.main "$AWS_IB_BUILD_COMP_ID"
fi

terraform -chdir="$TF_PATH" plan -out=./plan.out

if [ -t 0 ]; then
  echo ""
  read -p "Press enter to apply the plan..."
  echo ""
fi

echo "Applying plan..."
terraform -chdir="$TF_PATH" apply "./plan.out"