#!/bin/bash

S3_BACKEND=$(readConfig ".s3.mode" "hosted")

function setupBackendS3Rook() {
  if [[ "$S3_BACKEND" != "rook-block" ]]; then
    return
  fi

  echo ""
  echo "================= PREPARING FOR ROOK ================="

  source ./scripts/partials/rook-prepare.sh
  prepareRook
}

function configureBackendS3() {
  if [[ $S3_BACKEND == "rook-block" ]]; then
      pids=""
      for NODE in $(kubectl get nodes -l dedicated=services-infra -o json | jq -r '.items[].metadata.name'); do
          docker exec "$NODE" sh -c 'apt update && apt install -y lvm2' & pids="$pids $!"
      done
      wait $pids
  fi
}

function deployDependenciesS3() {
  if [[ $S3_BACKEND == "localstack" ]]; then
      sed -i "s/#{{DEPLOYMENT_ZONE}}/${DEPLOYMENT_ZONE}/g" ./utils/localstack.chart.yaml
      helm repo add localstack-repo https://helm.localstack.cloud || true
      helm upgrade --install localstack localstack-repo/localstack -f ./utils/localstack.chart.yaml & pids="$pids $!"
      kubectl apply -f ./utils/localstack-tracker/deployment.yaml
      kubectl apply -f ./utils/patch-operator/patch-s3-localstack.yaml
  fi
  if [[ $S3_BACKEND == "minio" ]]; then
      helm repo add bitnami https://charts.bitnami.com/bitnam || true
      helm upgrade --install minio bitnami/minio -f ./utils/minio.chart.yaml & pids="$pids $!"
  fi
  if [[ $S3_BACKEND == "rook-pvc-cinder" ]]; then
      helm repo add cpo https://kubernetes.github.io/cloud-provider-openstack || true
      helm upgrade --install cinder cpo/openstack-cinder-csi -f ./utils/cinder.chart.yaml & pids="$pids $!"
  fi
}

event on onClusterDependencies setupBackendS3Rook
event on onConfig configureBackendS3
event on postClusterDependencies deployDependenciesS3