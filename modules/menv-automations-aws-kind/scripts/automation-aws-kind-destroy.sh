#!/bin/bash

# ============================================================================
# Goal of this script is to automate creation of KIND cluster in AWS
# ============================================================================

set -e

if [[ -z "$INSTANCE_NAME" ]]; then
  echo "ERROR: INSTANCE_NAME is required via or using --instance-name arg"
  exit 1
fi

AWS_REGION=$(readConfig ".aws.region" "us-west-2")
DOMAIN_ZONE=$(readConfig ".aws.domain_zone" "kind.xyz")
export AWS_PAGER=""
echo "AWS region '$AWS_REGION'"

INSTANCE_DOMAIN="env-${INSTANCE_NAME}.${DOMAIN_ZONE}"
echo "Using domain '$INSTANCE_DOMAIN'"

echo "Checking if EC2 instance exists..."
if checkIfEc2InstanceExists; then
  echo "Deleting EC2 instance..."
  ID=$(aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:CLUSTER_NAME,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[InstanceId]' --output text)
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $ID
fi

echo "Checking if Route53 entry exists..."
ROUTE_EXISTS=0
if aws route53 list-resource-record-sets --hosted-zone-id Z05963611FE269SCWKWHH | jq -r '.ResourceRecordSets[].Name' | grep "\\\052.${INSTANCE_DOMAIN}." -q; then
  IP_ADDRESS=$(aws route53 list-resource-record-sets --hosted-zone-id Z05963611FE269SCWKWHH | jq --arg domain "\\052.${INSTANCE_DOMAIN}." -r '.ResourceRecordSets[] | select(.Name==$domain) | .ResourceRecords[0].Value')
  ROUTE_EXISTS=1
fi

if [[ "$ROUTE_EXISTS" == 1 ]]; then
  echo "Deleting Route53 entry..."
  OUTPUT=$(aws route53 change-resource-record-sets \
    --hosted-zone-id Z05963611FE269SCWKWHH \
    --change-batch '
    {
      "Comment": "Delete record set for KinD"
      ,"Changes": [{
        "Action"              : "DELETE"
        ,"ResourceRecordSet"  : {
          "Name"              : "*.'"$INSTANCE_DOMAIN"'"
          ,"Type"             : "A"
          ,"TTL"              : 30
          ,"ResourceRecords"  : [{
              "Value"         : "'"$IP_ADDRESS"'"
          }]
        }
      }]
    }
    '
  )
  CHG_ID=$(echo $OUTPUT | jq -r ".ChangeInfo.Id")
  STATUS=""
  TIMEOUT=0
  while [[ "$STATUS" != "INSYNC" ]]; do
    STATUS=$(aws route53  get-change --id $CHG_ID | jq -r ".ChangeInfo.Status")
    echo "Current status of delete request: $STATUS"
    sleep 5
    TIMEOUT=$(( TIMEOUT + 1 ))
    if (( TIMEOUT == 10 )); then
      echo "Failed to delete route53 entry"
      exit 1
    fi
  done
fi

set +x
echo ""
echo "==========================================================================="
echo "Cluster successfully deleted!"
echo "==========================================================================="
echo ""