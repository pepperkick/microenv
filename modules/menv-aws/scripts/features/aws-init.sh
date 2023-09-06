#!/bin/bash

function validateAwsCli() {
  export EC2_INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  export EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
  export EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

  if which aws; then
    aws --version
  else
    echo "ERROR: AWS CLI is required to fetch certs with 's3' mode"
    exit 1
  fi
}

event on onStartup validateAwsCli