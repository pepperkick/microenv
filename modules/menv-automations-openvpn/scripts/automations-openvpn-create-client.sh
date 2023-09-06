#!/bin/bash

# ============================================================================
# Goal of this script is to create a new client for openvpn
# ============================================================================

if which ssh; then
  ssh -V
else
  echo "ERROR: ssh cli is required"
  exit 1
fi

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

SSH_HOST=$(readConfig ".openvpn.ssh.host" "")
SSH_USER=$(readConfig ".openvpn.ssh.user" "ec2-user")
SSH_PORT=$(readConfig ".openvpn.ssh.port" "22")
SSH_KEY=$(readConfig ".openvpn.ssh.key" "./key.pem")

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
if which ssh; then
  zip
else
  yum install -y zip
fi
mkdir -p "./dist"
zip --junk-paths -r "/tmp/${CLIENT_NAME}.zip" "pki/ca.crt" "./pki/issued/${CLIENT_NAME}.crt" "./pki/private/${CLIENT_NAME}.key"
chmod 777 "/tmp/${CLIENT_NAME}.zip"
EOF

ssh -p ${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SSH_HOST} "bash -s" -- < ./tmp.sh
rm ./tmp.sh

scp -P ${SSH_PORT} -i ${SSH_KEY} ${SSH_USER}@${SSH_HOST}:/tmp/${CLIENT_NAME}.zip ./client.zip

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