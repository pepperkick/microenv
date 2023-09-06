#!/bin/bash

# ============================================================================
# Goal of this script is to add new nodes to existing KIND cluster
# NOTE: This is not officially supported by KIND
# ============================================================================

TARGET_NODES="${@:2}"
IFS=' ' read -r -a TARGET_NODES <<< "$TARGET_NODES"

controlPlaneName="${CLUSTER_NAME}-control-plane"
# TODO: Match image versioning with kubeadm config version
defaultImage=$(readConfig ".cluster.kind.nodes.image" "kindest/node:v1.25.9@sha256:c08d6c52820aa42e533b70bce0c2901183326d86dcdcbedecc9343681db45161")

# Check if control plane node exists
if ! docker ps -a | grep "$controlPlaneName"; then
  echo "ERROR: Control plane node $controlPlaneName not found"
  exit 1
fi

# Create node for each name provided
for element in "${TARGET_NODES[@]}"
do
  if [[ "$element" == "--"* ]]; then
    continue
  fi

  nodeName="${CLUSTER_NAME}-${element}"

  # Check if node exists
  if docker ps -a | grep "$nodeName"; then
    echo "ERROR: A node with name $nodeName already exists"
    exit 1
  fi

  echo ""
  echo "Creating node $nodeName..."

  # Create the node docker container
  docker run --name $nodeName --hostname $nodeName \
    --label io.x-k8s.kind.role=worker \
    --label io.x-k8s.kind.cluster=${CLUSTER_NAME} \
    --label io.x-k8s.kind.dynamic="yes" \
    --privileged \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    --tmpfs /tmp --tmpfs /run \
    --volume /var --volume /lib/modules:/lib/modules:ro \
    -e KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER \
    --detach --tty \
    --net kind \
    --restart=on-failure:1 \
    --init=false \
    $defaultImage

  # Get assigned IP of the new node
  nodeIpAddress=$(docker inspect $nodeName | jq -r ".[].NetworkSettings.Networks.kind.IPAddress")

  # Get additional configs
  clusterPodSubnet=$(docker exec $controlPlaneName cat /kind/kubeadm.conf | yq "select(di == 0).networking.podSubnet")
  clusterServiceSubnet=$(docker exec $controlPlaneName cat /kind/kubeadm.conf | yq "select(di == 0).networking.serviceSubnet")

  # Generate the kubeadm.conf file for new node
  docker exec "$nodeName" sh -c "cat <<-EOF >/kind/kubeadm.conf
apiServer:
  certSANs:
  - localhost
  - 0.0.0.0
  extraArgs:
    runtime-config: ""
apiVersion: kubeadm.k8s.io/v1beta3
clusterName: ${CLUSTER_NAME}
controlPlaneEndpoint: ${controlPlaneName}:6443
controllerManager:
  extraArgs:
    enable-hostpath-provisioner: \"true\"
kind: ClusterConfiguration
kubernetesVersion: v1.25.9
networking:
  podSubnet: ${clusterPodSubnet}
  serviceSubnet: ${clusterServiceSubnet}
scheduler:
  extraArgs: null
---
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- token: abcdef.0123456789abcdef
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${nodeIpAddress}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: ${nodeIpAddress}
    provider-id: kind://docker/${CLUSTER_NAME}/${nodeName}
---
apiVersion: kubeadm.k8s.io/v1beta3
discovery:
  bootstrapToken:
    apiServerEndpoint: ${CLUSTER_NAME}-control-plane:6443
    token: abcdef.0123456789abcdef
    unsafeSkipCAVerification: true
kind: JoinConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: ${nodeIpAddress}
    provider-id: kind://docker/${CLUSTER_NAME}/${nodeName}
---
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
cgroupRoot: /kubelet
evictionHard:
  imagefs.available: 0%
  nodefs.available: 0%
  nodefs.inodesFree: 0%
failSwapOn: false
imageGCHighThresholdPercent: 100
kind: KubeletConfiguration
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
conntrack:
  maxPerCore: 0
iptables:
  minSyncPeriod: 1s
kind: KubeProxyConfiguration
mode: iptables
EOF
"

  # Join the node
  docker exec "$nodeName" kubeadm join --config /kind/kubeadm.conf --skip-phases=preflight --v=6

  # Update the containerd service file
  if [[ $(readConfig ".machine.docker.local_registry.enabled" "false") != "true" ]]; then
    if [[ $(readConfig ".machine.proxy.enabled" "true") == "true" ]]; then
      docker exec "$nodeName" sh -c "mkdir -p /etc/systemd/system/containerd.service.d/ && cat <<-EOF >/etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment='HTTP_PROXY=$(readConfig ".machine.proxy.http_endpoint" "http://proxy:3128/")'
Environment='HTTPS_PROXY=$(readConfig ".machine.proxy.https_endpoint" "http://proxy:3128/")'
Environment='NO_PROXY=$(readConfig ".machine.proxy.exclusions" "169.254.169.254"),${IP_SUBNET}.0/16,10.96.0.0/16,192.168.0.0/16'
EOF
"
      docker exec "$nodeName" sh -c 'systemctl daemon-reload'
      docker exec "$nodeName" sh -c 'systemctl restart containerd'
    fi
  fi

  echo "Created node $nodeName"
done