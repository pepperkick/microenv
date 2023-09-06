function registerKindClusterIngressConfig() {
config="$(cat <<EOF
    server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;

        resolver 127.0.0.11 valid=30s;

        server_name .${DEPLOYMENT_ZONE};

        # SSL
        ssl_certificate /etc/nginx/ssl/certs/cert-bundle.pem;
        ssl_certificate_key /etc/nginx/ssl/certs/key.pem;

        # reverse proxy
        location / {
            set \$upstream https://${CLUSTER_NAME}-control-plane:32443;
            proxy_pass \$upstream;
            proxy_set_header Host            \$host;
            proxy_set_header X-Forwarded-For \$remote_addr;
        }
    }
EOF
)"

  registerIngressHttpServerConfigSnippet "$config"

config="$(cat <<EOF
    server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;

        resolver 127.0.0.11 valid=30s;

        server_name .dashpit.${DEPLOYMENT_ZONE};

        # SSL
        ssl_certificate /etc/nginx/ssl/certs/cert-bundle.pem;
        ssl_certificate_key /etc/nginx/ssl/certs/key.pem;

        # reverse proxy
        location / {
            set \$upstream http://${IP_SUBNET}:2080;
            proxy_pass \$upstream;
            proxy_set_header Host            \$host;
            proxy_set_header X-Forwarded-For \$remote_addr;
        }
    }
EOF
)"

  registerIngressHttpServerConfigSnippet "$config"

  # Configure additional domains
  length=$(readArrayLength ".ingress.domains")

  if [[ "$length" -gt "0" ]]; then
    for index in `seq 0 $length`;do
      name=$(readConfig ".ingress.domains[$index]")
config="$(cat <<EOF
      server {
          listen 443 ssl http2;
          listen [::]:443 ssl http2;

          resolver 127.0.0.11 valid=30s;

          server_name .$name;

          # SSL
          ssl_certificate /etc/nginx/ssl/certs/aws.cert.pem;
          ssl_certificate_key /etc/nginx/ssl/certs/aws.key.pem;

          # reverse proxy
          location / {
              set \$upstream https://${CLUSTER_NAME}-control-plane:32443;
              proxy_pass \$upstream;
              proxy_set_header Host            \$host;
              proxy_set_header X-Forwarded-For \$remote_addr;
          }
      }
EOF
)"

      registerIngressHttpServerConfigSnippet "$config"
    done
  fi
}

event on preIngressServerDeploy registerKindClusterIngressConfig