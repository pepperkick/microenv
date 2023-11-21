function setupEc2Ssm() {
  if which amazon-ssm-agent; then
    amazon-ssm-agent --version
    return
  fi

  if which dnf; then
    dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
  elif which yum; then
    if cat /etc/yum.conf | grep prxoy; then
      sed -i "s/proxy=.*/proxy=$(readConfig ".machine.proxy.http_endpoint" "http://proxy:3128/")/g" /etc/yum.conf
    else
      echo "proxy=$(readConfig ".machine.proxy.http_endpoint" "http://proxy:3128/")" >> /etc/yum.conf
    fi
    yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
  else
    echo "No supported package manager found, skipping aws ssm install."
  fi
}

function setEc2MetadataHop() {
  aws ec2 modify-instance-metadata-options \
    --instance-id $EC2_INSTANCE_ID \
    --http-put-response-hop-limit 3 \
    --http-endpoint enabled \
    --region $EC2_REGION
}

event on preSystemSetup setupEc2Ssm
event on postSystemSetup setEc2MetadataHop