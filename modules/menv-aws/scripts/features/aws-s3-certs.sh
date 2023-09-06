#!/bin/bash

function setupS3Certificates() {
  echo "Fetching Certs for $DEPLOYMENT_ZONE from S3..."
  path=$(readConfig ".ingress.certs.s3.path")

  if [[ -z "$path" ]]; then
    echo "ERROR: S3 path is required to fetch certs with 's3' mode"
    exit 1
  fi

  if which aws; then
    aws --version
  else
    echo "ERROR: AWS CLI is required to fetch certs with 's3' mode"
    exit 1
  fi

  mkdir -p ./certs
  aws s3 cp "$path/${DEPLOYMENT_ZONE}.zip" "certs.zip"
  unzip ./certs.zip -d ./certs-tmp
  for dir in ./certs-tmp/${INSTANCE_DOMAIN}; do
    cp "$dir/cert.pem" "./certs/cert.pem";
    cp "$dir/fullchain.pem" "./certs/cert-bundle.pem";
    cp "$dir/fullchain.pem" "./certs/tls.crt";
    cp "$dir/privkey.pem" "./certs/key.pem";
    cp "$dir/privkey.pem" "./certs/tls.key";
  done
  rm -rf ./certs-tmp || true
}

event on onIngressCertsProcess_s3 setupS3Certificates