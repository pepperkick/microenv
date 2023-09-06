#!/bin/bash

function setupRoute53Dns() {
  echo "Creating DNS entry for $DEPLOYMENT_ZONE in Route53..."

  IP_ADDRESS=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
  hostedZone=$(readConfig ".dns.route53.hosted_zone")

  if [[ -z "$hostedZone" ]]; then
    echo "ERROR: Hosted Zone is required for DNS entry with 'route53' mode"
    exit 1
  fi

  ROUTE_EXISTS=0
  if aws route53 list-resource-record-sets --hosted-zone-id $hostedZone | jq -r '.ResourceRecordSets[].Name' | grep "\\\052.${DEPLOYMENT_ZONE}." -q; then
    OLD_IP_ADDRESS=$(aws route53 list-resource-record-sets --hosted-zone-id $hostedZone | jq --arg domain "\\052.${DEPLOYMENT_ZONE}." -r '.ResourceRecordSets[] | select(.Name==$domain) | .ResourceRecords[0].Value')
    ROUTE_EXISTS=1
  fi

  if [[ "$OLD_IP_ADDRESS" == "$IP_ADDRESS" ]]; then
    echo "Route53 already has updated IP $IP_ADDRESS"
    return
  fi

  if [[ "$ROUTE_EXISTS" == 1 ]]; then
    aws route53 change-resource-record-sets \
      --hosted-zone-id $hostedZone \
      --change-batch '
      {
        "Comment": "Delete record set for KinD"
        ,"Changes": [{
          "Action"              : "DELETE"
          ,"ResourceRecordSet"  : {
            "Name"              : "*.'"$DEPLOYMENT_ZONE"'"
            ,"Type"             : "A"
            ,"TTL"              : 30
            ,"ResourceRecords"  : [{
                "Value"         : "'"$OLD_IP_ADDRESS"'"
            }]
          }
        }]
      }
      '
  fi

  # Add route53 entry
  aws route53 change-resource-record-sets \
    --hosted-zone-id $hostedZone \
    --change-batch '
     {
       "Comment": "Create record set for KinD"
       ,"Changes": [{
         "Action"              : "CREATE"
         ,"ResourceRecordSet"  : {
           "Name"              : "*.'"$DEPLOYMENT_ZONE"'"
           ,"Type"             : "A"
           ,"TTL"              : 30
           ,"ResourceRecords"  : [{
               "Value"         : "'"$IP_ADDRESS"'"
           }]
         }
       }]
     }
     '
}

event on onDnsEntryProcess_route53 setupRoute53Dns