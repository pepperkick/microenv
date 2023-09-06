#!/bin/bash

function setupLetsencryptCertificates() {
  echo ""
  echo "================ GENERATING CERTS ================"
  echo "Generating Certs for $DEPLOYMENT_ZONE using Letsencrypt..."

  email=$(readConfig ".ingress.certs.letsencrypt.email")
  challenge=$(readConfig ".ingress.certs.letsencrypt.challenge")

  if [[ -z "$email" ]]; then
    echo "ERROR: Email is required to fetch certs with 'letsencrypt' mode"
    exit 1
  fi

  if [[ -f "./certs/gen/live/$DEPLOYMENT_ZONE/privkey.pem" ]] && [[ -f "./certs/gen/live/$DEPLOYMENT_ZONE/fullchain.pem" ]]; then
    echo "Certs for domain $DEPLOYMENT_ZONE are already available. Reusing it."
  elif [[ "$challenge" == "route53" ]]; then
    docker run -v "$PWD/certs/gen:/etc/letsencrypt" -v "$PWD/certs/gen/lib:/var/lib/letsencrypt" --rm certbot/dns-route53 certonly --dns-route53 -d *.$DEPLOYMENT_ZONE --non-interactive --agree-tos --email $email
  else
    echo "ERROR: Unsupported challenge $challenge for letsencrypt"
    exit 1
  fi

  cp ./certs/gen/live/$DEPLOYMENT_ZONE/privkey.pem ./certs/key.pem
  cp ./certs/gen/live/$DEPLOYMENT_ZONE/fullchain.pem ./certs/cert-bundle.pem
  cp ./certs/gen/live/$DEPLOYMENT_ZONE/cert.pem ./certs/cert.pem
}

event on onIngressCertsProcess_letsencrypt setupLetsencryptCertificates