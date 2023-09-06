#!/bin/bash

REGISTRY_CONTAINER_NAME="$CLUSTER_NAME-docker-registry-proxy"
DNS_CONTAINER_NAME="$CLUSTER_NAME-dnsmasq"
INGRESS_CONTAINER_NAME="$CLUSTER_NAME-ingress"
NFS_CONTAINER_NAME="$CLUSTER_NAME-nfs"

kind delete cluster --name $CLUSTER_NAME

docker stop "${INGRESS_CONTAINER_NAME}" && docker rm "${INGRESS_CONTAINER_NAME}"
docker stop "${DNS_CONTAINER_NAME}" && docker rm "${DNS_CONTAINER_NAME}"
docker stop "${REGISTRY_CONTAINER_NAME}" && docker rm "${REGISTRY_CONTAINER_NAME}"
docker stop "${NFS_CONTAINER_NAME}" && docker rm "${NFS_CONTAINER_NAME}"