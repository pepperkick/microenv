function checkIfEc2InstanceExists() {
  length=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:CLUSTER_NAME,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    | jq ".Reservations | length")

  if [[ "$length" == "0" ]]; then
    return 1
  fi

  return 0
}

function sendSsmCommand() {
  SSM_OUTPUT_BUCKET=$(readConfig ".aws.ssm.output.bucket" "automations")
  SSM_OUTPUT_PATH=$(readConfig ".aws.ssm.output.path" "build/logs")
  COMMAND=$(aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids "$1" \
    --parameters commands="$2" \
    --parameters timeoutSeconds="14400" \
    --timeout-seconds 14400 --max-concurrency "50" --max-errors "0" \
    --output-s3-bucket-name "$SSM_OUTPUT_BUCKET" \
    --output-s3-key-prefix "$SSM_OUTPUT_PATH" \
    --region $AWS_REGION)
  RETURN_CODE=$?
  if [[ "$RETURN_CODE" == "0" ]]; then
    COMMAND_ID=$(echo "$COMMAND" | jq -r ".Command.CommandId")
  fi
  return $RETURN_CODE
}

function waitForSsmCommand() {
  RETRY=0
  while [[ "$STATUS" != "Success" ]]; do
    STATUS=$(aws ssm get-command-invocation \
      --command-id ${COMMAND_ID} \
      --instance-id ${INSTANCE_ID} | jq -r "StatusDetails")
    if (( $RETRY < 360 )); then
      RETRY=$(( $RETRY + 1 ))
      sleep 10
    else
      echo "Timeout waiting for command to finish."
      exit 1
    fi
  done

  aws ssm list-command-invocations --command-id "${COMMAND_ID}" --details --query "CommandInvocations[*].CommandPlugins[*].Output[]" --output text
}