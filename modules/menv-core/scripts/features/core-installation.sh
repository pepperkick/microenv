#!/bin/bash

function startInstallation() {
  mode=$(readConfig ".installation.mode" "helmfile")
  eventStage "InstallationProcess_$mode"
}

event on onInstallation startInstallation