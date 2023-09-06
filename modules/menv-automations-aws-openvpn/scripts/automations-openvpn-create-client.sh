#!/bin/bash

# ============================================================================
# Goal of this script is to create a new client for openvpn
# ============================================================================

ARGS="$@"

# Read arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --client-name)
      CLIENT_NAME="$2"
      shift
      shift
      ;;
    *)
      shift
      ;;
  esac
done

set -- ${ARGS[@]}

if [[ -z "$CLIENT_NAME" ]]; then
  echo "ERROR: CLIENT_NAME is required via env or using --client-name arg"
  exit 1
fi

AWS_INSTANCE=$(readConfig ".openvpn.aws.instance" "")
AWS_BUCKET=$(readConfig ".openvpn.aws.bucket" "automations")
AWS_PATH=$(readConfig ".openvpn.aws.path" "build/ovpn/clients")

SERVER_HOST=$(readConfig ".openvpn.server.host" "")
SERVER_PORT=$(readConfig ".openvpn.server.port" "1194")
SERVER_PROTOCOL=$(readConfig ".openvpn.server.protocol" "udp")
SERVER_EASYRSA_PATH=$(readConfig ".openvpn.server.easyrsa" "/home/ec2-user/easy-rsa")

CLIENT_EXPIRY=$(readConfig ".openvpn.clients.expire" "30")

cat <<EOF > ./tmp.sh
set -e
sudo su
cd $SERVER_EASYRSA_PATH
export EASYRSA_BATCH=1
export EASYRSA_CERT_EXPIRE=30
export EASYRSA_REQ_EMAIL="$CLIENT_NAME"
export EASYRSA_NS_COMMENT='OpenVPN Client for MicroEnv'
./easyrsa gen-req "$CLIENT_NAME" nopass
./easyrsa sign-req client "$CLIENT_NAME"
if which zip; then
  zip
else
  yum install -y zip
fi
mkdir -p "./dist"
zip --junk-paths -r "/tmp/${CLIENT_NAME}.zip" "pki/ca.crt" "./pki/issued/${CLIENT_NAME}.crt" "./pki/private/${CLIENT_NAME}.key"
aws s3 cp /tmp/${CLIENT_NAME}.zip s3://${AWS_BUCKET}/${AWS_PATH}/${CLIENT_NAME}/client.zip
EOF

aws s3 cp ./tmp.sh s3://${AWS_BUCKET}/${AWS_PATH}/${CLIENT_NAME}/script.sh
rm ./tmp.sh

commandId=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids "${AWS_INSTANCE}" \
  --parameters 'commands=["aws s3 cp s3://'"${AWS_BUCKET}"'/'"${AWS_PATH}"'/'"${CLIENT_NAME}"'/script.sh ./script.sh; chmod +x ./script.sh; ./script.sh"]'  \
  --output text --query "Command.CommandId")

aws ssm wait command-executed \
  --command-id "$commandId" \
  --instance-id "${AWS_INSTANCE}" \
  --output text --query "CommandStatus"

aws s3 cp s3://${AWS_BUCKET}/${AWS_PATH}/${CLIENT_NAME}/client.zip ./client.zip
aws s3 rm s3://${AWS_BUCKET}/${AWS_PATH}/${CLIENT_NAME}/script.sh
aws s3 rm s3://${AWS_BUCKET}/${AWS_PATH}/${CLIENT_NAME}/client.zip

cat <<EOF > ./client.ovpn
client
dev tun
proto ${SERVER_PROTOCOL}
remote ${SERVER_HOST} ${SERVER_PORT}
ca ca.crt
cert ${CLIENT_NAME}.crt
key ${CLIENT_NAME}.key
cipher AES-256-CBC
auth SHA512
auth-nocache
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
resolv-retry infinite
compress lz4
nobind
persist-key
persist-tun
mute-replay-warnings
verb 3
pull-filter ignore redirect-gateway
pull-filter ignore "dhcp-option DNS"
route-nopull
EOF

# Add routes for client config
length=$(readArrayLength ".openvpn.clients.routes")
for index in `seq 0 $length`; do
  route=$(readConfig ".openvpn.clients.routes[$index]")
  echo "route ${route} 255.255.255.0" >> ./client.ovpn
done

zip -r ./client.zip ./client.ovpn

echo ""
echo "==========================================================================="
echo "OpenVPN client successfully created!"
echo "==========================================================================="
echo ""