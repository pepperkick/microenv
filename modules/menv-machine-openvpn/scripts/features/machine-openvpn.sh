#!/bin/bash


function setupOpenVpn() {
  echo ""
  echo "================= SETTING UP OPENVPN ================="

  # Install openvpn packages
  yum install -y \
    https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/o/openvpn-2.4.12-1.el8.x86_64.rpm \
    https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/p/pkcs11-helper-1.22-7.el8.x86_64.rpm \
    iptables-services

  # Setup easyrsa
  curl -Lo easyrsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz
  tar -xvzf easyrsa.tgz
  mv EasyRSA-v3.0.6 easy-rsa

  cd easy-rsa

  # TODO: Make this configurable
cat <<EOF > ./vars
set_var EASYRSA                 "$PWD"
set_var EASYRSA_PKI             "$EASYRSA/pki"
set_var EASYRSA_DN              "cn_only"
set_var EASYRSA_REQ_COUNTRY     "NA"
set_var EASYRSA_REQ_PROVINCE    "NA"
set_var EASYRSA_REQ_CITY        "NA"
set_var EASYRSA_REQ_ORG         "NA"
set_var EASYRSA_REQ_EMAIL       "test@test.com"
set_var EASYRSA_REQ_OU          "NA"
set_var EASYRSA_NO_PASS         1
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_ALGO            rsa
set_var EASYRSA_CA_EXPIRE       7500
set_var EASYRSA_CERT_EXPIRE     365
set_var EASYRSA_NS_SUPPORT      "no"
set_var EASYRSA_REQ_CN          "microenv"
set_var EASYRSA_NS_COMMENT      "Microenv Cert"
set_var EASYRSA_EXT_DIR         "$EASYRSA/x509-types"
set_var EASYRSA_SSL_CONF        "$EASYRSA/openssl-easyrsa.cnf"
set_var EASYRSA_DIGEST          "sha256"
set_var EASYRSA_BATCH 			    "1"
EOF

  ./easyrsa init-pki
  ./easyrsa build-ca nopass
  ./easyrsa gen-req openvpn-server nopass
  ./easyrsa sign-req server openvpn-server
  ./easyrsa gen-dh
  openssl verify -CAfile pki/ca.crt pki/issued/openvpn-server.crt
  cp pki/ca.crt /etc/openvpn/server/
  cp pki/dh.pem /etc/openvpn/server/
  cp pki/private/openvpn-server.key /etc/openvpn/server/
  cp pki/issued/openvpn-server.crt /etc/openvpn/server/

cat <<EOF > "/etc/openvpn/server/server.conf"
port 1194
proto udp
dev tun
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/openvpn-server.crt
key /etc/openvpn/server/openvpn-server.key
dh /etc/openvpn/server/dh.pem
server 10.8.0.0 255.255.255.0
duplicate-cn
cipher AES-256-CBC
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
auth SHA512
auth-nocache
keepalive 20 60
persist-key
persist-tun
compress lz4
daemon
user nobody
group nobody
log-append /var/log/openvpn.log
verb 3
EOF

  systemctl start iptables
  systemctl enable iptables
  systemctl start openvpn-server@server
  systemctl enable openvpn-server@server

  # Configure system
  if cat /etc/sysctl.conf | grep "net.ipv4.ip_forward"; then
    echo ""
  else
    sysctl net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  fi

  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "eth0" -j MASQUERADE
  iptables -A FORWARD -s 10.8.0.0/24 -d 10.15.59.0/24 -j ACCEPT
  iptables -A FORWARD -d 10.8.0.0/24 -s 10.15.59.0/24 -j ACCEPT

  if [[ ! -d "/etc/iptables" ]]; then
    mkdir -p "/etc/iptables"
  fi

  iptables-save > /etc/iptables/rules.v4
  ip6tables-save > /etc/iptables/rules.v6
}