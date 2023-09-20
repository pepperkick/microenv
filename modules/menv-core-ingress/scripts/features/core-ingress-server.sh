#!/bin/bash

INGRESS_CONFIG_FILE="./configs/nginx.conf"

declare -a NGINX_INGRESS_HTTP_SERVER_CONFIGS

function initIngressServer() {
  export DEPLOYMENT_ZONE=$(readConfig ".ingress.domain" "abc.xyz")
  export INGRESS_CONTAINER_NAME="$CLUSTER_NAME-ingress"
}

function deployIngressServer() {
  echo ""
  echo "================= DEPLOYING INGRESS SERVER ================="

  event emit preIngressServerDeploy
  generateNginxConfig

  if resolvePath "$(readConfig ".ingress.certs.bundle" "./certs/cert-bundle.pem")"; then
    certBundle="$OUTPUT_RESOLVED_PATH"
  else
    echo "ERROR: $certBundle Cert bundle file not set or not found for ingress server"
    exit 1
  fi

  if resolvePath "$(readConfig ".ingress.certs.key" "./certs/key.pem")"; then
    certKey="$OUTPUT_RESOLVED_PATH"
  else
    echo "ERROR: $certKey Cert key file not set or not found for ingress server"
    exit 1
  fi

  event emit onIngressServerDeploy
  # Check if ingress container is already running, if so then stop and delete it
  docker ps -a | grep "$INGRESS_CONTAINER_NAME" && docker stop "$INGRESS_CONTAINER_NAME" && docker rm "$INGRESS_CONTAINER_NAME"

  # Deploy a new ingress server
  docker ps -a | grep "$INGRESS_CONTAINER_NAME" || \
  docker run -d --name $INGRESS_CONTAINER_NAME \
    --restart always --net kind --ip ${IP_SUBNET}.200 \
    --publish ${LISTEN_IP}:80:80 --publish ${LISTEN_IP}:443:443 \
    -v ${PWD}/${INGRESS_CONFIG_FILE}:/etc/nginx/nginx.conf \
    -v ${PWD}/certs:/etc/nginx/ssl/certs nginx

  event emit postIngressServerDeploy
}

function generateNginxConfig() {
cat <<EOF > ${INGRESS_CONFIG_FILE}
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] \$host "\$request" '
                      '\$status $body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    proxy_read_timeout 600;
    proxy_connect_timeout 600;
    proxy_send_timeout 600;

    server_names_hash_bucket_size 128;
    server_names_hash_max_size 512;

    client_max_body_size 0;

    underscores_in_headers on;
EOF

  for i in "${NGINX_INGRESS_HTTP_SERVER_CONFIGS[@]}"; do
cat <<EOF >> ${INGRESS_CONFIG_FILE}
$i
EOF
  done

cat <<EOF >> ${INGRESS_CONFIG_FILE}
}
EOF
}

function registerIngressHttpServerConfigSnippet() {
NGINX_INGRESS_HTTP_SERVER_CONFIGS+="$(cat <<EOF


$1
EOF
)"
}

event on onStartup initIngressServer
event on onClusterDependencies deployIngressServer