#!/bin/bash

# ============================================================================
# Goal of this script is to automate creation of KIND cluster in AWS
# ============================================================================

set -e

if [[ -z "$INSTANCE_NAME" ]]; then
  echo "ERROR: INSTANCE_NAME is required via env or using --instance-name arg"
  exit 1
fi

AWS_REGION=$(readConfig ".aws.region" "us-west-2")
DOMAIN_ZONE=$(readConfig ".aws.domain_zone" "kind.xyz")
BUILD_BUCKET=$(readConfig ".aws.build.bucket" "automations")
BUILD_PATH=$(readConfig ".aws.build.path" "build/microenv/packages")
MENV_BUCKET=$(readConfig ".aws.menv.bucket" "automations")
MENV_PATH=$(readConfig ".aws.menv.path" "build/microenv/distributions")
MENV_DIST=$(readConfig ".aws.menv.distribution" "menv-kind-helmfile")
LAUNCH_TEMPLATE_NAME=$(readConfig ".aws.resources.ec2_launch_template.name" "microenv-launcher")
echo "AWS region '$AWS_REGION'"

INSTANCE_DOMAIN="env-${INSTANCE_NAME}.${DOMAIN_ZONE}"
echo "Using domain '$INSTANCE_DOMAIN'"

# Create a copy of placeholder config
cp ./scripts/assets/placeholder-menv-config.yaml ./config.cluster.yaml

# Update config
INSTANCE_DOMAIN="$INSTANCE_DOMAIN" yq -i '.ingress.domain = env(INSTANCE_DOMAIN)' "./config.cluster.yaml"
aws s3 cp ./config.cluster.yaml "s3://${BUILD_BUCKET}/${BUILD_PATH}/config.${INSTANCE_NAME}.yaml"
echo "Generated cluster config file"

FILE="./tmp.startup.sh"
cat <<EOF > "$FILE"
#!/bin/bash

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -x
set -e

mkdir -p /home/ec2-user/menv
cd /home/ec2-user/menv
aws s3 cp s3://${MENV_BUCKET}/${MENV_PATH}/${MENV_DIST}.zip ./menv.zip
unzip -o ./menv.zip
aws s3 cp s3://${BUILD_BUCKET}/${BUILD_PATH}/config.${INSTANCE_NAME}.yaml ./config.yaml
./menv.sh create --config ./config.yaml --delete-cluster
EOF

echo "Using following script"
echo "====================="
cat "$FILE"
echo "====================="

echo "Checking if EC2 instance exists..."
# Create EC2 instance
if checkIfEc2InstanceExists; then
  echo "ERROR: An instance with name 'microenv-$INSTANCE_NAME' already exists"
  exit 1
fi

echo "Creating EC2 instance..."
aws ec2 run-instances \
  --region $AWS_REGION \
  --launch-template LaunchTemplateName="$LAUNCH_TEMPLATE_NAME" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=CLUSTER_NAME,Value=$INSTANCE_NAME},{Key=Name,Value=microenv-$INSTANCE_NAME},{Key=microenv,Value='true'},{Key=CREATED_AT,Value=$(date --utc +%FT%TZ)}]" \
  --user-data file://tmp.startup.sh \
  --output json

echo "Waiting for kubernetes to be up..."
RETRY=0
while curl --max-time 5 -k https://kube.${INSTANCE_DOMAIN}:55555; do
  if (( $RETRY < 150 )); then
    RETRY=$(( $RETRY + 1 ))
    sleep 10
  else
    echo "Timeout waiting for healthcheck."
    exit 1
  fi
done

echo ""
echo "==========================================================================="
echo "Cluster successfully created!"
echo "==========================================================================="
echo ""