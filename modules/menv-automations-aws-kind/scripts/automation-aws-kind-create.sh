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
LAUNCH_TEMPLATE_NAME=$(readConfig ".aws.resources.ec2_launch_template.name" "microenv-launcher")
echo "AWS region '$AWS_REGION'"

INSTANCE_DOMAIN="env-${INSTANCE_NAME}.${DOMAIN_ZONE}"
echo "Using domain '$INSTANCE_DOMAIN'"

# Generate startup script
MENV_BUILD_PATH=$(readConfig ".aws.menv.s3.build")
MENV_BUILD_CONTENTS=$(readConfig ".aws.menv.build")
MENV_CONFIG_PATH=$(readConfig ".aws.menv.s3.config")
MENV_CONFIG_CONTENTS=$(readConfig ".aws.menv.config" "./scripts/assets/placeholder-menv-config.yaml")
FILE="./tmp.startup.sh"
cat <<EOF > "$FILE"
#!/bin/bash

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -x
set -e

export INSTANCE_DOMAIN="${INSTANCE_DOMAIN}"

mkdir -p /home/ec2-user/microenv
cd /home/ec2-user/microenv
EOF

if [[ -z "$MENV_BUILD_PATH" ]]; then
cat <<EOF >> "$FILE"
cat <<EOS >build.yaml
${MENV_BUILD_CONTENTS}
EOS

curl -Lo ./build.sh https://raw.githubusercontent.com/pepperkick/microenv/main/build.sh
chmod +x ./build.sh
./build.sh -c ./build.yaml
EOF
else
cat <<EOF >> "$FILE"
aws s3 cp ${MENV_BUILD_PATH} ./menv.zip
EOF
fi

cat <<EOF >> "$FILE"
unzip -o ./menv.zip
EOF

if [[ -z "$MENV_CONFIG_PATH" ]]; then
cat <<EOF >> "$FILE"
cat <<EOS >config.yaml
${MENV_CONFIG_CONTENTS}
EOS
EOF
else
cat <<EOF >> "$FILE"
aws s3 cp ${MENV_CONFIG_PATH} ./config.yaml
EOF
fi

cat <<EOF >> "$FILE"
chmod +x ./menv.sh
./menv.sh create --config ./config.yaml --delete-cluster
EOF

echo ""
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

if [[ "$USE_SPOT_INSTANCE" == "true" ]]; then
  echo "Creating EC2 spot instance..."

  # Fetch the details of the launch template
  LAUNCH_TEMPLATE_DETAILS=$(aws ec2 describe-launch-template-versions --launch-template-name "$LAUNCH_TEMPLATE_NAME" --query 'LaunchTemplateVersions[0].LaunchTemplateData' --output json)

  # Extract the details needed for the launch specification
  LAUNCH_TEMPLATE_DETAILS=$(echo "$LAUNCH_TEMPLATE_DETAILS" | jq "del(.InstanceInitiatedShutdownBehavior)" | jq "del(.TagSpecifications)" | jq --arg var "$(base64 -w 0 $FILE)" '.UserData = $var')

  aws ec2 request-spot-instances \
    --region $AWS_REGION \
    --launch-specification "$LAUNCH_TEMPLATE_DETAILS" \
    --tag-specifications "ResourceType=spot-instances-request,Tags=[{Key=CLUSTER_NAME,Value=$INSTANCE_NAME},{Key=SPOT_INSTANCE,Value=true},{Key=Name,Value=microenv-$INSTANCE_NAME},{Key=microenv,Value='true'},{Key=CREATED_AT,Value=$(date --utc +%FT%TZ)}]" \
    --output json \
    --instance-count 1 \
    --type "one-time"
else
  echo "Creating EC2 instance..."
  aws ec2 run-instances \
    --region $AWS_REGION \
    --launch-template LaunchTemplateName="$LAUNCH_TEMPLATE_NAME" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=CLUSTER_NAME,Value=$INSTANCE_NAME},{Key=Name,Value=microenv-$INSTANCE_NAME},{Key=microenv,Value='true'},{Key=CREATED_AT,Value=$(date --utc +%FT%TZ)}]" \
    --user-data file://$FILE \
    --output json
fi

echo "Waiting for kubernetes to be up..."
RETRY=0
while ! curl --max-time 5 -k https://kube.${INSTANCE_DOMAIN}:55555; do
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