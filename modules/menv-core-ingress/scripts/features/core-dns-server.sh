#!/bin/bash

DNSMASQ_CONFIG_FILE="./configs/dnsmasq.conf"
COREDNS_CONFIG_FILE="./configs/coredns.yaml"

function deployDnsServer() {
  if [[ "$(readConfig ".dns.enabled" "true")" == "false" ]]; then
    return
  fi

  echo ""
  echo "================= DEPLOYING DNS SERVER ================="

  generateDnsmasqConfig

  # Check if DNS server container is already running, if so then stop and delete it
  docker ps -a | grep "$DNS_CONTAINER_NAME" && docker stop $DNS_CONTAINER_NAME && docker rm $DNS_CONTAINER_NAME

  # Deploy new DNS server container
  docker ps -a | grep "$DNS_CONTAINER_NAME" || \
  docker run --restart always -d \
    --name "$DNS_CONTAINER_NAME" \
    --cap-add=NET_ADMIN --net=kind --ip ${IP_SUBNET}.180 \
    --hostname "$DNS_CONTAINER_NAME" \
    -v ${PWD}/${DNSMASQ_CONFIG_FILE}:/etc/dnsmasq.conf \
    jpillora/dnsmasq
}

function configureCoreDns() {
  if [[ "$(readConfig ".dns.enabled" "true")" == "true" ]] || [[ "$(readConfig ".dns.disable_coredns_patch" "false")" == "true" ]]; then
    return
  fi

  generateCorednsConfig

  # Patch coredns configmap to point to DNS server
  kubectl patch configmap/coredns -n kube-system --patch-file "./installer-configs/coredns.yaml"
  kubectl rollout restart deployment coredns -n kube-system
}

function generateDnsmasqConfig() {
  echo "Generating dnsmasq config file"

cat <<EOF > ${DNSMASQ_CONFIG_FILE}
log-queries
no-resolv
strict-order
server=8.8.8.8
server=8.8.4.4
address=/${DEPLOYMENT_ZONE}/${IP_SUBNET}.200
EOF

  # Configure additional domains
  length=$(readArrayLength ".dns.domains")

  if [[ "$length" -gt "0" ]]; then
    for index in `seq 0 $length`;do
      name=$(readConfig ".dns.domains[$index]")
      echo "address=/${name}/${IP_SUBNET}.200" >> ${DNSMASQ_CONFIG_FILE}
    done
  fi
}

function generateCorednsConfig() {
  echo "Generating coredns config file"

cat <<EOF > ${COREDNS_CONFIG_FILE}
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }

    ${DEPLOYMENT_ZONE}:53 {
        errors
        cache 30
        forward . ${IP_SUBNET}.180
    }
EOF

  # Configure additional domains
  length=$(readArrayLength ".dns.domains")

  if [[ "$length" -gt "0" ]]; then
    for index in `seq 0 $length`;do
      name=$(readConfig ".dns.domains[$index]")
cat <<EOF >> ${COREDNS_CONFIG_FILE}

    ${name}:53 {
        errors
        cache 30
        forward . ${IP_SUBNET}.180
    }
EOF
    done
  fi
}

event on onClusterDependencies deployDnsServer
event on onConfig configureCoreDns