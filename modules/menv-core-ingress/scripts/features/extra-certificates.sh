#!/bin/bash

function setupCertificates() {
  mode=$(readConfig ".ingress.certs.mode" "manual")
  eventStage "IngressCertsProcess_$mode"
}

function setupManualCertificates() {
    # TODO: Ensure certs exist
    return
}

event on preSetup setupCertificates
event on onIngressCertsProcess_manual setupManualCertificates