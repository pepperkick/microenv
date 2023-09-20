#!/bin/bash

function setupLetsencryptCertificates() {
  domain=$(readConfig ".ingress.domain" "abc.xyz")
  email=$(readConfig ".ingress.certs.letsencrypt.email")
  challenge=$(readConfig ".ingress.certs.letsencrypt.challenge" "route53")

  echo ""
  echo "================ GENERATING CERTS ================"
  echo "Generating Certs for $domain using Letsencrypt..."

  if [[ -z "$email" ]]; then
    echo "ERROR: Email is required to fetch certs with 'letsencrypt' mode"
    exit 1
  fi

  if [[ -f "./certs/gen/live/$domain/privkey.pem" ]] && [[ -f "./certs/gen/live/$domain/fullchain.pem" ]]; then
    echo "Certs for domain $domain are already available. Reusing it."
  elif [[ "$challenge" == "route53" ]]; then
    docker run -v "$PWD/certs/gen:/etc/letsencrypt" -v "$PWD/certs/gen/lib:/var/lib/letsencrypt" --rm certbot/dns-route53 \
      certonly \
      --dns-route53 -d *.$domain \
      --non-interactive --agree-tos \
      --email $email
  else
    echo "ERROR: Unsupported challenge $challenge for letsencrypt"
    exit 1
  fi

  cp ./certs/gen/live/$domain/privkey.pem ./certs/key.pem
  cp ./certs/gen/live/$domain/fullchain.pem ./certs/cert-bundle.pem
  cp ./certs/gen/live/$domain/cert.pem ./certs/cert.pem
}

event on onIngressCertsProcess_letsencrypt setupLetsencryptCertificates