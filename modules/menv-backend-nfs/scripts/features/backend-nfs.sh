#!/bin/bash

NFS_BACKEND=$(readConfig ".nfs.mode" "docker")

function deployBackendNfs() {
  if [[ $NFS_BACKEND != "docker" ]]; then
    return
  fi

  echo ""
  echo "================= DEPLOYING NFS SERVER ================="

  event emit preNfsDockerDeploy
  event emit onNfsDockerDeploy

  # Enable kernel modules
  modprobe nfs || true
  modprobe nfsd || true

  # Deploy a new nfs server
  docker ps -a | grep "$NFS_CONTAINER_NAME" || \
  docker run -d --name $NFS_CONTAINER_NAME --restart always --net kind --ip ${IP_SUBNET}.160 -v /mnt/server --privileged -e NFS_EXPORT_0='/mnt/server *(rw,no_root_squash,no_subtree_check,fsid=0)' erichough/nfs-server

  event emit postNfsDockerDeploy
}

function deployDependenciesNfs() {
  if [[ $NFS_BACKEND == "provisioner" ]]; then
      helm upgrade --install nfs-server stable/nfs-server-provisioner & pids="$pids $!"
  fi
}

event on onClusterDependencies deployDependenciesNfs
event on onClusterDependencies deployBackendNfs