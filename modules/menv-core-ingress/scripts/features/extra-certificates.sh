#!/bin/bash

function setupCertificates() {
  mode=$(readConfig ".ingress.certs.mode" "manual")
  eventStage "IngressCertsProcess_$mode"
}

function setupManualCertificates() {
  # TODO: Ensure certs exist
  return
}

function setupSelfSignedCertificates() {
  echo ""
  echo "================ GENERATING CERTS ================"
  echo "Generating Self Signed Certs for $domain..."

  docker run -v "$PWD/certs/ssc:/certs" -e SSL_SUBJECT=$domain stakater/ssl-certs-generator:1.0

  cp ./certs/ssc/key.pem ./certs/key.pem
  cp ./certs/ssc/cert.pem ./certs/cert-bundle.pem
  cp ./certs/ssc/cert.pem ./certs/cert.pem

  return
}

event on preSetup setupCertificates
event on onIngressCertsProcess_manual setupManualCertificates
event on onIngressCertsProcess_selfSigned setupSelfSignedCertificates