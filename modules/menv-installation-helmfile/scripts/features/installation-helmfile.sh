#!/bin/bash

function startHelmfileInstallation() {
  echo ""
  echo "================= INSTALLING FROM HELMFILE ================="

  if which helmfile; then
    helmfile --version
  else
    curl -Lo ./helmfile.tar.gz https://github.com/helmfile/helmfile/releases/download/v0.156.0/helmfile_0.156.0_linux_amd64.tar.gz
    tar -xvzf ./helmfile.tar.gz
    chmod +x ./helmfile
    mv ./helmfile /usr/bin/helmfile
  fi

  if ! helm diff version; then
    helm plugin install https://github.com/databus23/helm-diff
  fi

  releaseFile=$(readConfig ".installation.helmfile.path" "./helmfile.yaml")

  if [[ -z "$releaseFile" ]]; then
    echo "ERROR: Release file required for 'helmfile' installation"
    exit 1
  fi

  releaseFile=$(abspath $releaseFile)
  echo "Using helmfile release file '$releaseFile'"

  environment=$(readConfig ".installation.helmfile.environment" "default")
  cmd="helmfile --file=$releaseFile --environment=$environment apply"

  length=$(readArrayLength ".installation.helmfile.value_files")
  if [[ "$length" -gt "0" ]]; then
    path=$(readConfig ".installation.helmfile.value_files[$index]")
    cmd=$(echo "$cmd --state-values-file=$(abspath $path)")
  fi

  cmd=$(echo "$cmd --state-values-file=$(abspath $MICRO_ENV_CONFIG_FILE)")

  if [[ "$DEBUG_ENABLED" == "true" ]]; then
    cmd=$(echo "$cmd --debug")
  fi

  echo "Executing command -- $cmd"

  ${cmd}
}

event on onInstallationProcess_helmfile startHelmfileInstallation